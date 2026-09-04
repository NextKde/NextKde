// kos-data-service owns persistent shell telemetry. It deliberately has no
// GUI dependencies: Quickshell consumes it over the kos-data.sock JSONL API;
// snapshot.json is only the service's own persisted state, not a QML input.
package main

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/fsnotify/fsnotify"
	"golang.org/x/sys/unix"
)

// MetricSample keeps one fixed-interval telemetry point. Ratios are 0..1 and
// temperatures are in millidegrees Celsius, so every consumer formats the same
// canonical units without touching /proc itself.
type MetricSample struct {
	At            int64   `json:"at"`
	CPU           float64 `json:"cpu,omitempty"`
	Memory        float64 `json:"memory,omitempty"`
	Disk          float64 `json:"disk,omitempty"`
	Frequency     float64 `json:"frequencyMhz,omitempty"`
	CurrentMilliC float64 `json:"currentMilliC,omitempty"`
	AverageMilliC float64 `json:"averageMilliC,omitempty"`
	MaximumMilliC float64 `json:"maximumMilliC,omitempty"`
}
type Metrics struct {
	CPU                  float64         `json:"cpu"`
	Memory               float64         `json:"memory"`
	Disk                 float64         `json:"disk"`
	FrequencyMHz         float64         `json:"frequencyMhz"`
	CurrentMilliC        float64         `json:"currentMilliC"`
	Maximum5MinuteMilliC float64         `json:"maximum5MinuteMilliC"`
	AverageMilliC        float64         `json:"averageMilliC"`
	MaximumMilliC        float64         `json:"maximumMilliC"`
	MemoryUsedBytes      float64         `json:"memoryUsedBytes"`
	MemoryTotalBytes     float64         `json:"memoryTotalBytes"`
	DiskUsedBytes        float64         `json:"diskUsedBytes"`
	DiskTotalBytes       float64         `json:"diskTotalBytes"`
	Sensors              []SensorReading `json:"sensors"`
	History              []MetricSample  `json:"history"`
}

// SensorReading is one live hwmon/thermal reading, enumerated exactly like the
// old shell sampler so the sensor dashboard keeps its device/label detail.
type SensorReading struct {
	Source string  `json:"source"`
	Device string  `json:"device"`
	Label  string  `json:"label"`
	MilliC float64 `json:"milliC"`
}

const temperaturePeakWindow = 5 * time.Minute

type AppUsage struct {
	Name    string  `json:"name,omitempty"`
	Icon    string  `json:"icon,omitempty"`
	Seconds float64 `json:"seconds"`
}
type Activity struct {
	Active        bool                `json:"active"`
	ActiveApp     string              `json:"activeApp,omitempty"`
	TodayApps     map[string]AppUsage `json:"todayApps"`
	UptimeByDay   map[string]float64  `json:"uptimeByDay"`
	JournalSeeded bool                `json:"journalSeeded"`
}
type DesktopEntry struct {
	Name       string `json:"name"`
	Title      string `json:"title,omitempty"`
	Path       string `json:"path"`
	Kind       string `json:"kind"`
	Icon       string `json:"icon,omitempty"`
	ModifiedAt int64  `json:"modifiedAt"`
}
type Desktop struct {
	Directory string         `json:"directory"`
	Entries   []DesktopEntry `json:"entries"`
	UpdatedAt int64          `json:"updatedAt"`
}
type Snapshot struct {
	SchemaVersion int          `json:"schemaVersion"`
	GeneratedAt   int64        `json:"generatedAt"`
	Metrics       Metrics      `json:"metrics"`
	Activity      Activity     `json:"activity"`
	Desktop       Desktop      `json:"desktop"`
	Weather       WeatherState `json:"weather"`
}
type State struct {
	Metrics  Metrics      `json:"metrics"`
	Activity Activity     `json:"activity"`
	Desktop  Desktop      `json:"desktop"`
	Weather  WeatherState `json:"weather"`
}
type DataRequest struct {
	Version   int                    `json:"version"`
	RequestID string                 `json:"requestId"`
	Operation string                 `json:"operation"`
	Payload   map[string]interface{} `json:"payload"`
}

type DataResponse struct {
	Version   int         `json:"version"`
	RequestID string      `json:"requestId,omitempty"`
	OK        bool        `json:"ok"`
	Result    interface{} `json:"result,omitempty"`
	Error     *DataError  `json:"error,omitempty"`
}

type DataError struct {
	Code      string `json:"code"`
	Message   string `json:"message"`
	Retryable bool   `json:"retryable"`
}

type Service struct {
	mu                        sync.Mutex
	desktopSubscribersMu      sync.Mutex
	desktopSubscribers        map[net.Conn]struct{}
	state                     State
	statePath, snapshotPath   string
	desktopDirectory          string
	weatherProvider           WeatherProvider
	weatherRequestSerial      uint64
	last                      time.Time
	prevCPUTotal, prevCPUIdle float64
}

func day(t time.Time) string { return t.Format("2006-01-02") }
func homePath(env, fallback string) string {
	if v := os.Getenv(env); v != "" {
		return v
	}
	return fallback
}

func newService() *Service {
	home, _ := os.UserHomeDir()
	stateRoot := homePath("XDG_STATE_HOME", filepath.Join(home, ".local", "state"))
	root := filepath.Join(stateRoot, "quickshell", "shell-data-service")
	s := &Service{
		statePath:          filepath.Join(root, "state.json"),
		snapshotPath:       filepath.Join(root, "snapshot.json"),
		desktopDirectory:   desktopDirectory(),
		desktopSubscribers: map[net.Conn]struct{}{},
		weatherProvider:    newOpenMeteoProvider(),
		last:               time.Now(),
	}
	s.state.Activity.TodayApps = map[string]AppUsage{}
	s.state.Activity.UptimeByDay = map[string]float64{}
	if raw, err := os.ReadFile(s.statePath); err == nil {
		_ = json.Unmarshal(raw, &s.state)
	}
	if s.state.Activity.TodayApps == nil {
		s.state.Activity.TodayApps = map[string]AppUsage{}
	}
	if s.state.Activity.UptimeByDay == nil {
		s.state.Activity.UptimeByDay = map[string]float64{}
	}
	normalizeWeatherState(&s.state.Weather)
	return s
}

func writeJSON(path string, value any) error {
	raw, err := json.Marshal(value)
	if err != nil {
		return err
	}
	if err = os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		return err
	}
	tmp := path + ".tmp"
	if err = os.WriteFile(tmp, raw, 0644); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}
func (s *Service) persist() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.settle(time.Now())
	snapshot := Snapshot{
		SchemaVersion: 1,
		GeneratedAt:   time.Now().UnixMilli(),
		Metrics:       s.state.Metrics,
		Activity:      s.state.Activity,
		Desktop:       s.state.Desktop,
		Weather:       s.state.Weather,
	}
	_ = writeJSON(s.statePath, s.state)
	_ = writeJSON(s.snapshotPath, snapshot)
}

// subscribeDesktop turns the existing local event socket into a small
// notification channel as well. QML keeps one connection open and only reads
// the snapshot after a change notification, so neither side polls a directory.
func (s *Service) subscribeDesktop(conn net.Conn) {
	s.desktopSubscribersMu.Lock()
	_, alreadySubscribed := s.desktopSubscribers[conn]
	s.desktopSubscribers[conn] = struct{}{}
	s.desktopSubscribersMu.Unlock()
	if alreadySubscribed {
		return
	}
	// The atomic snapshot is created before the socket starts listening. A new
	// subscriber is therefore always prompted to consume one complete current
	// directory state instead of waiting for the next filesystem mutation.
	_ = conn.SetWriteDeadline(time.Now().Add(100 * time.Millisecond))
	event := map[string]interface{}{"version": 1, "event": "desktop.changed",
		"payload": map[string]interface{}{"updatedAt": time.Now().UnixMilli()}}
	raw, _ := json.Marshal(event)
	_, _ = conn.Write(append(raw, '\n'))
	// Clear the absolute deadline: it must not leak into the long-lived request
	// loop, or every response written after this 100ms window would time out
	// (which is why the shell only ever received its first metrics snapshot).
	_ = conn.SetWriteDeadline(time.Time{})
}

func (s *Service) unsubscribeDesktop(conn net.Conn) {
	s.desktopSubscribersMu.Lock()
	delete(s.desktopSubscribers, conn)
	s.desktopSubscribersMu.Unlock()
}

func (s *Service) publishDesktop() {
	s.desktopSubscribersMu.Lock()
	defer s.desktopSubscribersMu.Unlock()
	for conn := range s.desktopSubscribers {
		_ = conn.SetWriteDeadline(time.Now().Add(100 * time.Millisecond))
		event := map[string]interface{}{"version": 1, "event": "desktop.changed",
			"payload": map[string]interface{}{"updatedAt": time.Now().UnixMilli()}}
		raw, _ := json.Marshal(event)
		if _, err := conn.Write(append(raw, '\n')); err != nil {
			delete(s.desktopSubscribers, conn)
			_ = conn.Close()
			continue
		}
		// Do not leave the 100ms broadcast deadline armed on the shared
		// connection; the request loop would otherwise inherit it and time out.
		_ = conn.SetWriteDeadline(time.Time{})
	}
}

// Weather shares the connection registry with desktop events. Holding the
// same write mutex prevents two asynchronous broadcasts from interleaving on
// a JSONL connection.
func (s *Service) publishWeather() {
	s.desktopSubscribersMu.Lock()
	defer s.desktopSubscribersMu.Unlock()
	for conn := range s.desktopSubscribers {
		_ = conn.SetWriteDeadline(time.Now().Add(100 * time.Millisecond))
		event := map[string]interface{}{"version": 1, "event": "weather.changed",
			"payload": map[string]interface{}{"updatedAt": time.Now().UnixMilli()}}
		raw, _ := json.Marshal(event)
		if _, err := conn.Write(append(raw, '\n')); err != nil {
			delete(s.desktopSubscribers, conn)
			_ = conn.Close()
			continue
		}
		_ = conn.SetWriteDeadline(time.Time{})
	}
}

func desktopDirectory() string {
	if output, err := exec.Command("xdg-user-dir", "DESKTOP").Output(); err == nil {
		if directory := strings.TrimSpace(string(output)); directory != "" {
			return directory
		}
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, "Desktop")
}

func desktopKind(entry os.DirEntry) string {
	if entry.IsDir() {
		return "folder"
	}
	extension := strings.ToLower(filepath.Ext(entry.Name()))
	switch extension {
	case ".desktop":
		return "launcher"
	case ".png", ".jpg", ".jpeg", ".webp", ".gif", ".svg":
		return "image"
	case ".pdf":
		return "pdf"
	case ".md", ".txt", ".rst":
		return "text"
	case ".py", ".go", ".js", ".ts", ".qml", ".sh", ".json", ".yaml", ".yml":
		return "code"
	default:
		return "file"
	}
}

func desktopLauncherPresentation(path string) (string, string) {
	file, err := os.Open(path)
	if err != nil {
		return "", ""
	}
	defer file.Close()

	inEntry := false
	name, icon := "", ""
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "[Desktop Entry]" {
			inEntry = true
			continue
		}
		if inEntry && strings.HasPrefix(line, "[") {
			break
		}
		if !inEntry || strings.HasPrefix(line, "#") {
			continue
		}
		key, value, found := strings.Cut(line, "=")
		if !found {
			continue
		}
		switch key {
		case "Name":
			name = strings.TrimSpace(value)
		case "Icon":
			icon = strings.TrimSpace(value)
		}
	}
	return name, icon
}

func readDesktop(directory string) Desktop {
	desktop := Desktop{Directory: directory, Entries: []DesktopEntry{}}
	entries, err := os.ReadDir(directory)
	if err != nil {
		return desktop
	}
	for _, entry := range entries {
		// Match standard desktop behaviour: dot-files are managed by their
		// owning applications and do not appear as desktop icons by default.
		if strings.HasPrefix(entry.Name(), ".") {
			continue
		}
		info, err := entry.Info()
		if err != nil {
			continue
		}
		kind := desktopKind(entry)
		title, icon := "", ""
		if kind == "launcher" {
			title, icon = desktopLauncherPresentation(filepath.Join(directory, entry.Name()))
		}
		desktop.Entries = append(desktop.Entries, DesktopEntry{
			Name: entry.Name(), Path: filepath.Join(directory, entry.Name()),
			Title: title, Kind: kind, Icon: icon, ModifiedAt: info.ModTime().UnixMilli(),
		})
	}
	sort.SliceStable(desktop.Entries, func(left, right int) bool {
		leftFolder := desktop.Entries[left].Kind == "folder"
		rightFolder := desktop.Entries[right].Kind == "folder"
		if leftFolder != rightFolder {
			return leftFolder
		}
		if desktop.Entries[left].ModifiedAt != desktop.Entries[right].ModifiedAt {
			return desktop.Entries[left].ModifiedAt > desktop.Entries[right].ModifiedAt
		}
		return strings.ToLower(desktop.Entries[left].Name) < strings.ToLower(desktop.Entries[right].Name)
	})
	desktop.UpdatedAt = time.Now().UnixMilli()
	return desktop
}

func (s *Service) refreshDesktop() bool {
	desktop := readDesktop(s.desktopDirectory)
	s.mu.Lock()
	defer s.mu.Unlock()
	previous := s.state.Desktop
	// The update time is intentionally excluded: unchanged directory scans do
	// not churn the atomic snapshot or wake the QML consumer.
	previous.UpdatedAt = 0
	comparison := desktop
	comparison.UpdatedAt = 0
	if reflect.DeepEqual(previous, comparison) {
		return false
	}
	s.state.Desktop = desktop
	return true
}

// watchDesktop is the primary source of desktop-file updates. Event bursts
// from editors, sync clients, and atomic replaces become one snapshot write.
func watchDesktop(s *Service) {
	watcher, err := fsnotify.NewWatcher()
	if err != nil {
		fmt.Fprintln(os.Stderr, "desktop watcher:", err)
		return
	}
	defer watcher.Close()
	if err := watcher.Add(s.desktopDirectory); err != nil {
		fmt.Fprintln(os.Stderr, "desktop watcher add:", err)
		return
	}

	const debounce = 100 * time.Millisecond
	var timer *time.Timer
	var timerC <-chan time.Time
	scheduleRefresh := func() {
		if timer == nil {
			timer = time.NewTimer(debounce)
			timerC = timer.C
			return
		}
		if !timer.Stop() {
			select {
			case <-timer.C:
			default:
			}
		}
		timer.Reset(debounce)
		// timerC is cleared after every delivery. Reattach it here so every
		// subsequent filesystem burst, not just the first one, reaches select.
		timerC = timer.C
	}
	for {
		select {
		case event, ok := <-watcher.Events:
			if !ok {
				return
			}
			if event.Op&(fsnotify.Create|fsnotify.Remove|fsnotify.Rename|fsnotify.Write) != 0 {
				scheduleRefresh()
			}
		case err, ok := <-watcher.Errors:
			if !ok {
				return
			}
			fmt.Fprintln(os.Stderr, "desktop watcher event:", err)
			scheduleRefresh()
		case <-timerC:
			timerC = nil
			if s.refreshDesktop() {
				s.persist()
				s.publishDesktop()
			}
		}
	}
}

// parseF64 reads a /proc or /sys file that holds a single non-negative number.
func parseF64(path string) float64 {
	raw, err := os.ReadFile(path)
	if err != nil {
		return 0
	}
	value, err := strconv.ParseFloat(strings.TrimSpace(string(raw)), 64)
	if err != nil || value < 0 {
		return 0
	}
	return value
}

// readCPU returns the machine-wide CPU busy ratio between this call and the
// previous one. The first call after a restart reports 0 because there is no
// prior /proc/stat delta to compare against.
func (s *Service) readCPU() float64 {
	raw, err := os.ReadFile("/proc/stat")
	if err != nil {
		return 0
	}
	fields := strings.Fields(strings.SplitN(string(raw), "\n", 2)[0])
	if len(fields) < 5 {
		return 0
	}
	total, idle := float64(0), float64(0)
	for i := 1; i < len(fields); i++ {
		n, _ := strconv.ParseFloat(fields[i], 64)
		total += n
		if i == 4 || i == 5 {
			idle += n
		}
	}
	if s.prevCPUTotal > 0 && total > s.prevCPUTotal {
		usage := 1 - (idle-s.prevCPUIdle)/(total-s.prevCPUTotal)
		s.prevCPUTotal = total
		s.prevCPUIdle = idle
		return math.Max(0, math.Min(1, usage))
	}
	s.prevCPUTotal = total
	s.prevCPUIdle = idle
	return 0
}

func readMem() (used, total float64) {
	raw, err := os.ReadFile("/proc/meminfo")
	if err != nil {
		return 0, 0
	}
	memTotal, memAvailable := float64(0), float64(0)
	for _, l := range strings.Split(string(raw), "\n") {
		f := strings.Fields(l)
		if len(f) < 2 {
			continue
		}
		v, _ := strconv.ParseFloat(f[1], 64)
		switch f[0] {
		case "MemTotal:":
			memTotal = v
		case "MemAvailable:":
			memAvailable = v
		}
	}
	if memTotal <= 0 {
		return 0, 0
	}
	// /proc/meminfo counts in kibibytes.
	used = math.Max(0, memTotal-memAvailable)
	return used * 1024, memTotal * 1024
}

func readDisk() (used, total float64) {
	raw, err := os.ReadFile("/proc/mounts")
	if err != nil {
		return 0, 0
	}
	for _, line := range strings.Split(string(raw), "\n") {
		fields := strings.Fields(line)
		if len(fields) < 2 || fields[1] != "/" {
			continue
		}
		if out, err := exec.Command("df", "-B1", "--output=used,size", "/").Output(); err == nil {
			if rows := strings.Split(strings.TrimSpace(string(out)), "\n"); len(rows) >= 2 {
				values := strings.Fields(rows[1])
				if len(values) == 2 {
					used, _ = strconv.ParseFloat(values[0], 64)
					total, _ = strconv.ParseFloat(values[1], 64)
					return used, total
				}
			}
		}
		break
	}
	return 0, 0
}

func readFrequency() float64 {
	// Prefer the live cpufreq policies; the /proc/cpuinfo fallback covers
	// machines without an intel_pstate/CPUFreq driver reporting a current rate.
	entries, _ := filepath.Glob("/sys/devices/system/cpu/cpufreq/policy*/scaling_cur_freq")
	sum, count := float64(0), float64(0)
	for _, p := range entries {
		if value := parseF64(p); value > 0 {
			sum += value
			count++
		}
	}
	if count > 0 {
		return sum / count / 1000 // kHz -> MHz
	}
	raw, err := os.ReadFile("/proc/cpuinfo")
	if err != nil {
		return 0
	}
	sum, count = 0, 0
	for _, line := range strings.Split(string(raw), "\n") {
		fields := strings.Fields(line)
		if len(fields) >= 4 && fields[0] == "cpu" && fields[1] == "MHz" {
			if value, err := strconv.ParseFloat(fields[3], 64); err == nil {
				sum += value
				count++
			}
		}
	}
	if count == 0 {
		return 0
	}
	return sum / count
}

// cpuTemperaturePriority selects one canonical package-level reading instead
// of averaging duplicate ACPI, thermal-zone, and per-core views of the same
// processor. Direct hwmon package sensors are preferred, then package thermal
// zones, with CPU-labelled zones and individual cores as fallbacks.
func cpuTemperaturePriority(reading SensorReading) int {
	if reading.MilliC <= 0 {
		return 0
	}
	source := strings.ToLower(reading.Source)
	device := strings.ToLower(reading.Device)
	label := strings.ToLower(reading.Label)

	switch {
	case device == "coretemp" && strings.Contains(label, "package id"):
		return 100
	case (device == "k10temp" || strings.Contains(device, "zenpower")) && label == "tctl":
		return 100
	case (device == "k10temp" || strings.Contains(device, "zenpower")) && label == "tdie":
		return 95
	case source == "thermal" && label == "x86_pkg_temp":
		return 90
	case strings.Contains(label, "package") || strings.Contains(label, "pkg"):
		return 80
	case source == "thermal" && strings.Contains(label, "tcpu"):
		return 70
	case device == "coretemp" && strings.HasPrefix(label, "core "):
		return 60
	case source == "thermal" && strings.Contains(label, "cpu"):
		return 50
	default:
		return 0
	}
}

func selectCurrentCPUTemperature(readings []SensorReading) float64 {
	priority := 0
	current := float64(-1)
	for _, reading := range readings {
		candidatePriority := cpuTemperaturePriority(reading)
		if candidatePriority == 0 || candidatePriority < priority {
			continue
		}
		if candidatePriority > priority || reading.MilliC > current {
			priority = candidatePriority
			current = reading.MilliC
		}
	}
	return current
}

func readTemperature() (current float64, readings []SensorReading) {
	zones, _ := filepath.Glob("/sys/class/thermal/thermal_zone*/type")
	for _, t := range zones {
		label := strings.TrimSpace(string(readRaw(t)))
		index := strings.TrimPrefix(t, "/sys/class/thermal/thermal_zone")
		index = strings.TrimSuffix(index, "/type")
		if !strings.Contains(strings.ToLower(label), "cpu") &&
			!strings.Contains(strings.ToLower(label), "pkg") {
			continue
		}
		value := parseF64("/sys/class/thermal/thermal_zone" + index + "/temp")
		readings = append(readings, SensorReading{
			Source: "thermal", Device: "kernel", Label: label, MilliC: value,
		})
	}
	hwmons, _ := filepath.Glob("/sys/class/hwmon/hwmon*")
	for _, hwmon := range hwmons {
		device := strings.TrimSpace(string(readRaw(hwmon + "/name")))
		inputs, _ := filepath.Glob(hwmon + "/temp*_input")
		for _, input := range inputs {
			index := strings.TrimPrefix(input, hwmon+"/temp")
			index = strings.TrimSuffix(index, "_input")
			label := strings.TrimSpace(string(readRaw(hwmon + "/temp" + index + "_label")))
			if label == "" {
				label = "Temperature " + index
			}
			readings = append(readings, SensorReading{
				Source: "hwmon", Device: device, Label: label, MilliC: parseF64(input),
			})
		}
	}
	return selectCurrentCPUTemperature(readings), readings
}

func metricSampleTemperature(sample MetricSample) float64 {
	if sample.CurrentMilliC > 0 {
		return sample.CurrentMilliC
	}
	// State written before currentMilliC existed stored an instantaneous
	// thermal-zone maximum and average. Prefer the former during the five-minute
	// migration window so an actual recent peak is not understated.
	if sample.MaximumMilliC > 0 {
		return sample.MaximumMilliC
	}
	if sample.AverageMilliC > 0 {
		return sample.AverageMilliC
	}
	return -1
}

func rollingTemperatureMaximum(history []MetricSample, nowMillis int64, window time.Duration) float64 {
	cutoff := nowMillis - window.Milliseconds()
	maximum := float64(-1)
	for _, sample := range history {
		if sample.At < cutoff || sample.At > nowMillis {
			continue
		}
		if value := metricSampleTemperature(sample); value > maximum {
			maximum = value
		}
	}
	return maximum
}

// readRaw returns a file's bytes trimmed of whitespace; missing/unreadable
// files yield an empty slice so callers never fail on virtual filesystems.
func readRaw(path string) []byte {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil
	}
	return []byte(strings.TrimSpace(string(raw)))
}

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
	listRaw, err := exec.Command("journalctl", "--list-boots", "--no-pager").Output()
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
		s.addInterval(first*1000, last*1000, "")
		s.mu.Unlock()
	}
	s.mu.Lock()
	s.state.Activity.JournalSeeded = true
	s.mu.Unlock()
}

// addInterval credits seconds between start and end (epoch millis) to the
// matching calendar day. App attribution is empty for online time only.
func (s *Service) addInterval(start, end float64, appID string) {
	if end <= start {
		return
	}
	// State written by early versions and focused test fixtures may omit these
	// maps. Recreate them before settling time so persistence cannot panic.
	if s.state.Activity.UptimeByDay == nil {
		s.state.Activity.UptimeByDay = map[string]float64{}
	}
	if s.state.Activity.TodayApps == nil {
		s.state.Activity.TodayApps = map[string]AppUsage{}
	}
	for cursor := start; cursor < end; {
		date := time.UnixMilli(int64(cursor))
		tomorrow := time.Date(date.Year(), date.Month(), date.Day()+1, 0, 0, 0, 0, time.Local)
		segmentEnd := math.Min(end, float64(tomorrow.UnixMilli()))
		seconds := (segmentEnd - cursor) / 1000
		if seconds > 0 {
			key := day(date)
			if appID == "" {
				s.state.Activity.UptimeByDay[key] += seconds
			} else {
				app := s.state.Activity.TodayApps[appID]
				app.Seconds += seconds
				s.state.Activity.TodayApps[appID] = app
			}
		}
		cursor = segmentEnd
	}
}

// settle credits the wall-clock seconds since the last call into today's
// uptime bucket and, while a foreground app is tracked, that app's session
// total. The sub-120s guard ignores long pauses (suspend, clock jumps).
func (s *Service) settle(now time.Time) {
	seconds := now.Sub(s.last).Seconds()
	if seconds > 0 && seconds < 120 {
		s.addInterval(float64(s.last.UnixMilli()), float64(now.UnixMilli()), "")
		if s.state.Activity.Active && s.state.Activity.ActiveApp != "" {
			app := s.state.Activity.TodayApps[s.state.Activity.ActiveApp]
			app.Seconds += seconds
			s.state.Activity.TodayApps[s.state.Activity.ActiveApp] = app
		}
	}
	s.last = now
}

func (s *Service) sample() {
	s.mu.Lock()
	defer s.mu.Unlock()
	now := time.Now()
	current, readings := readTemperature()
	memUsed, memTotal := readMem()
	diskUsed, diskTotal := readDisk()
	cpu := s.readCPU()
	frequency := readFrequency()
	s.state.Metrics.CPU = cpu
	// Ratios must stay finite: a failed probe yields NaN, which json.Marshal
	// rejects and would silently kill the whole snapshot write.
	if memTotal > 0 {
		s.state.Metrics.Memory = memUsed / memTotal
	}
	if diskTotal > 0 {
		s.state.Metrics.Disk = diskUsed / diskTotal
	}
	s.state.Metrics.FrequencyMHz = frequency
	s.state.Metrics.CurrentMilliC = current
	s.state.Metrics.MemoryUsedBytes = memUsed
	s.state.Metrics.MemoryTotalBytes = memTotal
	s.state.Metrics.DiskUsedBytes = diskUsed
	s.state.Metrics.DiskTotalBytes = diskTotal
	s.state.Metrics.Sensors = readings
	sample := MetricSample{At: now.UnixMilli(), CPU: cpu, Memory: s.state.Metrics.Memory,
		Disk: s.state.Metrics.Disk, Frequency: frequency, CurrentMilliC: current,
		// Keep writing the old fields for one compatibility cycle. New readers
		// consume currentMilliC and maximum5MinuteMilliC.
		AverageMilliC: current, MaximumMilliC: current}
	s.state.Metrics.History = append(s.state.Metrics.History, sample)
	if len(s.state.Metrics.History) > 360 {
		s.state.Metrics.History = s.state.Metrics.History[len(s.state.Metrics.History)-360:]
	}
	maximum5Minute := rollingTemperatureMaximum(
		s.state.Metrics.History, now.UnixMilli(), temperaturePeakWindow)
	s.state.Metrics.Maximum5MinuteMilliC = maximum5Minute
	// Compatibility aliases keep older shell surfaces correct while every
	// in-tree consumer migrates to the explicit field names.
	s.state.Metrics.AverageMilliC = current
	s.state.Metrics.MaximumMilliC = maximum5Minute
}
func dataError(request DataRequest, code, message string, retryable bool) DataResponse {
	return DataResponse{Version: 1, RequestID: request.RequestID, OK: false,
		Error: &DataError{Code: code, Message: message, Retryable: retryable}}
}

func (s *Service) handleRequest(request DataRequest) DataResponse {
	if request.Version != 0 && request.Version != 1 {
		return dataError(request, "unsupported-version", "不支持的协议版本", false)
	}
	switch request.Operation {
	case "metrics.snapshot":
		s.mu.Lock()
		metrics := s.state.Metrics
		s.mu.Unlock()
		return DataResponse{Version: 1, RequestID: request.RequestID, OK: true,
			Result: map[string]interface{}{"metrics": metrics}}
	case "activity.snapshot":
		s.mu.Lock()
		activity := s.state.Activity
		s.mu.Unlock()
		return DataResponse{Version: 1, RequestID: request.RequestID, OK: true,
			Result: map[string]interface{}{"activity": activity}}
	case "desktop.snapshot":
		s.mu.Lock()
		desktop := s.state.Desktop
		s.mu.Unlock()
		return DataResponse{Version: 1, RequestID: request.RequestID, OK: true,
			Result: map[string]interface{}{"desktop": desktop}}
	case "desktop.refresh":
		if s.refreshDesktop() {
			s.persist()
			s.publishDesktop()
		}
		return DataResponse{Version: 1, RequestID: request.RequestID, OK: true,
			Result: map[string]interface{}{"refreshed": true}}
	case "weather.snapshot":
		s.mu.Lock()
		weather := s.state.Weather
		s.mu.Unlock()
		return DataResponse{Version: 1, RequestID: request.RequestID, OK: true,
			Result: map[string]interface{}{"weather": weather}}
	case "weather.search":
		query, _ := request.Payload["query"].(string)
		language, _ := request.Payload["language"].(string)
		limit := 8
		if value, ok := request.Payload["limit"].(float64); ok {
			limit = int(value)
		}
		locations, err := s.searchWeather(query, language, limit)
		if err != nil {
			return dataError(request, "weather-search-failed", weatherErrorMessage(err), true)
		}
		return DataResponse{Version: 1, RequestID: request.RequestID, OK: true,
			Result: map[string]interface{}{"locations": locations}}
	case "weather.refresh":
		accepted := s.startWeatherRefresh(true)
		return DataResponse{Version: 1, RequestID: request.RequestID, OK: true,
			Result: map[string]interface{}{"accepted": accepted}}
	case "weather.set-location":
		raw, err := json.Marshal(request.Payload["location"])
		if err != nil {
			return dataError(request, "invalid-location", "天气位置格式无效", false)
		}
		var location WeatherLocation
		if err = json.Unmarshal(raw, &location); err != nil {
			return dataError(request, "invalid-location", "天气位置格式无效", false)
		}
		if err = s.setWeatherLocation(location); err != nil {
			return dataError(request, "invalid-location", weatherErrorMessage(err), false)
		}
		return DataResponse{Version: 1, RequestID: request.RequestID, OK: true}
	case "weather.set-units":
		units, _ := request.Payload["units"].(string)
		if err := s.setWeatherUnits(units); err != nil {
			return dataError(request, "invalid-units", weatherErrorMessage(err), false)
		}
		return DataResponse{Version: 1, RequestID: request.RequestID, OK: true}
	case "activity.active-app":
		appID, _ := request.Payload["appID"].(string)
		name, _ := request.Payload["name"].(string)
		icon, _ := request.Payload["icon"].(string)
		s.mu.Lock()
		s.settle(time.Now())
		s.state.Activity.ActiveApp = appID
		s.state.Activity.Active = appID != ""
		if appID != "" {
			app := s.state.Activity.TodayApps[appID]
			app.Name = name
			if icon != "" {
				app.Icon = icon
			}
			s.state.Activity.TodayApps[appID] = app
		}
		s.mu.Unlock()
		return DataResponse{Version: 1, RequestID: request.RequestID, OK: true}
	default:
		return dataError(request, "unknown-operation", "未知的数据操作", false)
	}
}

func serve(s *Service, path string) error {
	_ = os.Remove(path)
	l, err := net.Listen("unix", path)
	if err != nil {
		return err
	}
	_ = os.Chmod(path, 0600)
	defer l.Close()
	for {
		c, e := l.Accept()
		if e != nil {
			return e
		}
		go func() {
			defer c.Close()
			s.subscribeDesktop(c)
			defer s.unsubscribeDesktop(c)
			scanner := bufio.NewScanner(c)
			for scanner.Scan() {
				var request DataRequest
				if json.Unmarshal(scanner.Bytes(), &request) != nil {
					response := dataError(request, "invalid-json", "请求不是有效 JSON", false)
					raw, _ := json.Marshal(response)
					_ = c.SetWriteDeadline(time.Now().Add(2 * time.Second))
					_, _ = c.Write(append(raw, '\n'))
					continue
				}
				response := s.handleRequest(request)
				raw, _ := json.Marshal(response)
				// Re-arm a fresh deadline before every response: other write paths
				// (desktop broadcasts) leave a stale 100ms deadline on the shared
				// connection, and an absolute deadline never resets on its own.
				_ = c.SetWriteDeadline(time.Now().Add(2 * time.Second))
				_, _ = c.Write(append(raw, '\n'))
			}
		}()
	}
}

func acquireInstanceLock(socketPath string) (*os.File, error) {
	lockPath := socketPath + ".lock"
	lock, err := os.OpenFile(lockPath, os.O_CREATE|os.O_RDWR, 0600)
	if err != nil {
		return nil, fmt.Errorf("open service lock: %w", err)
	}
	if err = unix.Flock(int(lock.Fd()), unix.LOCK_EX|unix.LOCK_NB); err != nil {
		_ = lock.Close()
		return nil, fmt.Errorf("another kos-data-service instance is active: %w", err)
	}
	return lock, nil
}

func main() {
	s := newService()
	// KOS_DATA_SOCKET lets a development service listen beside the installed
	// one (see kosctl dev); the installed layout never sets it.
	socket := os.Getenv("KOS_DATA_SOCKET")
	if socket == "" {
		socket = filepath.Join(homePath("XDG_RUNTIME_DIR", "/tmp"), "kos-data.sock")
	}
	instanceLock, err := acquireInstanceLock(socket)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return
	}
	defer instanceLock.Close()
	// Publish the initial full directory snapshot before accepting subscribers.
	// This removes the startup race where QML connected while snapshot.json was
	// still stale and then waited indefinitely for a second filesystem event.
	s.sample()
	s.refreshDesktop()
	s.persist()
	s.startWeatherRefresh(false)
	go func() {
		if err := serve(s, socket); err != nil && !errors.Is(err, net.ErrClosed) {
			fmt.Fprintln(os.Stderr, err)
		}
	}()
	tick := time.NewTicker(10 * time.Second)
	// Uptime attribution settles every second so a crash or reload loses at
	// most one second instead of up to a minute. Metrics stay on the slower
	// tick; a 1s snapshot write every ten seconds is an atomic json write.
	settleTick := time.NewTicker(1 * time.Second)
	save := time.NewTicker(10 * time.Second)
	desktopReconcile := time.NewTicker(5 * time.Second)
	defer tick.Stop()
	defer settleTick.Stop()
	defer save.Stop()
	defer desktopReconcile.Stop()
	go s.seedJournalHistory()
	go watchDesktop(s)
	for {
		select {
		case <-tick.C:
			s.sample()
			s.startWeatherRefresh(false)
		case <-settleTick.C:
			s.mu.Lock()
			s.settle(time.Now())
			s.mu.Unlock()
		case <-save.C:
			s.persist()
		case <-desktopReconcile.C:
			// inotify is a wake-up optimization, not the source of truth. This
			// bounded reconciliation repairs a missed/overflowed event by reading
			// and publishing the complete directory state again.
			if s.refreshDesktop() {
				s.persist()
				s.publishDesktop()
			}
		}
	}
}
