package main

import (
	"math"
	"os/exec"
	"sort"
	"strconv"
	"strings"
	"time"
)

// uptimeDayLimit bounds the per-day uptime ledger. Keys are ISO calendar
// dates, so lexical order is chronological and the map can be trimmed by
// keeping the newest keys.
const uptimeDayLimit = 90

func day(t time.Time) string { return t.Format("2006-01-02") }

// journalTimestampFirst returns the first entry's epoch timestamp of a boot
// log without buffering the whole journal: head closes the pipe after one
// line, so journalctl stops writing after its first record. The shell's exit
// status is therefore 141 on a successful read; only the stdout line matters.
func journalTimestampFirst(boot string) float64 {
	out, err := exec.Command("sh", "-c",
		"exec journalctl -b \"$1\" -o short-unix --no-pager 2>/dev/null | head -n1",
		"journal-first", boot).Output()
	if err != nil && len(out) == 0 {
		return 0
	}
	return shortUnixTimestamp(strings.TrimSpace(string(out)))
}

// journalTimestampLast uses journalctl's own tail read, so a years-long boot
// log costs one line instead of an unbounded in-memory copy.
func journalTimestampLast(boot string) float64 {
	out, err := exec.Command("journalctl", "-b", boot, "-o", "short-unix",
		"--no-pager", "-n", "1").Output()
	if err != nil && len(out) == 0 {
		return 0
	}
	return shortUnixTimestamp(strings.TrimSpace(string(out)))
}

func shortUnixTimestamp(line string) float64 {
	if line == "" {
		return 0
	}
	// short-unix timestamps are epoch seconds with a fractional tail.
	parsed, err := strconv.ParseFloat(strings.SplitN(line, " ", 2)[0], 64)
	if err != nil || parsed <= 0 {
		return 0
	}
	return parsed
}

// seedJournalHistory attributes uptime from past boots recorded by journald.
// Only the boots before the current one are replayed; the running boot is
// settled incrementally by settle(). It runs in the background so the first
// snapshot is not delayed behind dozens of journalctl spawns, and each boot's
// ledger update holds the mutex only for the interval add itself.
func (s *Service) seedJournalHistory() {
	s.mu.Lock()
	seeded := s.state.Activity.JournalSeeded
	s.mu.Unlock()
	if seeded {
		return
	}
	listRaw, err := exec.Command("journalctl", "--list-boots", "--reverse",
		"--no-legend", "--no-pager").Output()
	if err != nil {
		return
	}
	boots := strings.Split(strings.TrimSpace(string(listRaw)), "\n")
	if len(boots) <= 1 {
		s.mu.Lock()
		s.state.Activity.JournalSeeded = true
		s.mu.Unlock()
		return
	}
	// The first listed boot is the current one; historical uptime starts at
	// the second. Boots beyond 84 stay outside the bounded daily view.
	limit := len(boots)
	if limit > 85 {
		limit = 85
	}
	for i := 1; i < limit; i++ {
		fields := strings.Fields(boots[i])
		if len(fields) == 0 {
			continue
		}
		boot := fields[0]
		first := journalTimestampFirst(boot)
		last := journalTimestampLast(boot)
		if last <= first {
			continue
		}
		s.mu.Lock()
		s.addInterval(first*1000, last*1000)
		s.mu.Unlock()
	}
	s.mu.Lock()
	s.state.Activity.JournalSeeded = true
	s.mu.Unlock()
}

// addInterval credits seconds between start and end (epoch millis) to the
// matching calendar day's uptime bucket. Per-app attribution lives in
// settle(), which only ever credits the current day.
func (s *Service) addInterval(start, end float64) {
	if end <= start {
		return
	}
	// State written by early versions and focused test fixtures may omit this
	// map. Recreate it before settling time so persistence cannot panic.
	if s.state.Activity.UptimeByDay == nil {
		s.state.Activity.UptimeByDay = map[string]float64{}
	}
	for cursor := start; cursor < end; {
		date := time.UnixMilli(int64(cursor))
		tomorrow := time.Date(date.Year(), date.Month(), date.Day()+1, 0, 0, 0, 0, time.Local)
		segmentEnd := math.Min(end, float64(tomorrow.UnixMilli()))
		seconds := (segmentEnd - cursor) / 1000
		if seconds > 0 {
			s.state.Activity.UptimeByDay[day(date)] += seconds
		}
		cursor = segmentEnd
	}
}

// rollDay performs the two calendar-day maintenance steps: TodayApps is a
// per-day view that must not carry yesterday's rows forward, and UptimeByDay
// is trimmed to a bounded trailing window so the persisted ledger cannot
// grow with every recorded day. It is cheap on the steady path — an equal
// day key and a ledger inside the limit return without allocating.
func (s *Service) rollDay(now time.Time) {
	today := day(now)
	if s.state.Activity.TodayAppsDay != today {
		s.state.Activity.TodayAppsDay = today
		// The still-foreground app re-enters with zeroed seconds but keeps
		// its name and icon, or the usage card renders a blank row until the
		// next focus change re-announces it.
		carry, existed := s.state.Activity.TodayApps[s.state.Activity.ActiveApp]
		s.state.Activity.TodayApps = map[string]AppUsage{}
		if existed && s.state.Activity.Active {
			s.state.Activity.TodayApps[s.state.Activity.ActiveApp] =
				AppUsage{Name: carry.Name, Icon: carry.Icon}
		}
	}
	if s.state.Activity.TodayApps == nil {
		s.state.Activity.TodayApps = map[string]AppUsage{}
	}
	if len(s.state.Activity.UptimeByDay) <= uptimeDayLimit {
		return
	}
	keys := make([]string, 0, len(s.state.Activity.UptimeByDay))
	for key := range s.state.Activity.UptimeByDay {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	for _, key := range keys[:len(keys)-uptimeDayLimit] {
		delete(s.state.Activity.UptimeByDay, key)
	}
}

// settle credits the wall-clock seconds since the last call into today's
// uptime bucket and, while a foreground app is tracked, that app's session
// total. The sub-120s guard ignores long pauses (suspend, clock jumps).
func (s *Service) settle(now time.Time) {
	s.rollDay(now)
	seconds := now.Sub(s.last).Seconds()
	if seconds > 0 && seconds < 120 {
		s.addInterval(float64(s.last.UnixMilli()), float64(now.UnixMilli()))
		if s.state.Activity.Active && s.state.Activity.ActiveApp != "" {
			app := s.state.Activity.TodayApps[s.state.Activity.ActiveApp]
			app.Seconds += seconds
			s.state.Activity.TodayApps[s.state.Activity.ActiveApp] = app
		}
	}
	s.last = now
}
