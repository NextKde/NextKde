package main

import (
	"bufio"
	"encoding/json"
	"net"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"
)

func TestSelectCurrentCPUTemperaturePrefersPackageSensor(t *testing.T) {
	readings := []SensorReading{
		{Source: "thermal", Device: "kernel", Label: "TCPU", MilliC: 77050},
		{Source: "thermal", Device: "kernel", Label: "x86_pkg_temp", MilliC: 77000},
		{Source: "hwmon", Device: "coretemp", Label: "Core 12", MilliC: 74000},
		{Source: "hwmon", Device: "coretemp", Label: "Package id 0", MilliC: 72000},
		{Source: "hwmon", Device: "nvme", Label: "Composite", MilliC: 88000},
	}

	if got := selectCurrentCPUTemperature(readings); got != 72000 {
		t.Fatalf("package temperature = %v, want 72000", got)
	}
}

func TestSelectCurrentCPUTemperatureFallsBackToPackageThermalZone(t *testing.T) {
	readings := []SensorReading{
		{Source: "thermal", Device: "kernel", Label: "TCPU", MilliC: 76050},
		{Source: "thermal", Device: "kernel", Label: "x86_pkg_temp", MilliC: 75000},
		{Source: "hwmon", Device: "coretemp", Label: "Core 0", MilliC: 79000},
	}

	if got := selectCurrentCPUTemperature(readings); got != 75000 {
		t.Fatalf("fallback package temperature = %v, want 75000", got)
	}
}

func TestRollingTemperatureMaximumUsesFiveMinuteWindow(t *testing.T) {
	now := time.Date(2026, 8, 25, 12, 0, 0, 0, time.UTC).UnixMilli()
	history := []MetricSample{
		{At: now - int64(6*time.Minute/time.Millisecond), CurrentMilliC: 99000},
		// Legacy sample: no currentMilliC, so maximumMilliC is the fallback.
		{At: now - int64(4*time.Minute/time.Millisecond), AverageMilliC: 78000, MaximumMilliC: 81000},
		{At: now - int64(2*time.Minute/time.Millisecond), CurrentMilliC: 74000},
		{At: now, CurrentMilliC: 70000},
	}

	if got := rollingTemperatureMaximum(history, now, 5*time.Minute); got != 81000 {
		t.Fatalf("rolling maximum = %v, want 81000", got)
	}
}

func TestDesktopSubscriptionImmediatelyAnnouncesSnapshot(t *testing.T) {
	service := &Service{desktopSubscribers: map[*subscriberConn]struct{}{}}
	server, client := net.Pipe()
	defer server.Close()
	defer client.Close()

	done := make(chan struct{})
	go func() {
		service.subscribeDesktop(&subscriberConn{Conn: server})
		close(done)
	}()
	line, err := bufio.NewReader(client).ReadString('\n')
	if err != nil {
		t.Fatal(err)
	}
	var event struct {
		Version int                    `json:"version"`
		Event   string                 `json:"event"`
		Payload map[string]interface{} `json:"payload"`
	}
	if err := json.Unmarshal([]byte(line), &event); err != nil {
		t.Fatalf("invalid event %q: %v", line, err)
	}
	if event.Version != 1 || event.Event != "desktop.changed" {
		t.Fatalf("unexpected initial notification %#v", event)
	}
	<-done
}

func TestRefreshDesktopReconcilesCompleteDirectory(t *testing.T) {
	directory := t.TempDir()
	service := &Service{desktopDirectory: directory}

	if !service.refreshDesktop() {
		t.Fatal("initial directory state was not accepted")
	}
	if service.refreshDesktop() {
		t.Fatal("unchanged directory produced a false update")
	}
	path := filepath.Join(directory, "first.txt")
	if err := os.WriteFile(path, []byte("first"), 0600); err != nil {
		t.Fatal(err)
	}
	if !service.refreshDesktop() {
		t.Fatal("new file was not found by complete reconciliation")
	}
	if len(service.state.Desktop.Entries) != 1 ||
		service.state.Desktop.Entries[0].Path != path {
		t.Fatalf("unexpected desktop snapshot: %#v", service.state.Desktop.Entries)
	}
}

func TestRollDayResetsTodayAppsOnDayChange(t *testing.T) {
	service := &Service{}
	service.state.Activity.TodayAppsDay = "2026-09-19"
	service.state.Activity.TodayApps = map[string]AppUsage{
		"firefox": {Name: "Firefox", Seconds: 300},
	}
	service.state.Activity.UptimeByDay = map[string]float64{"2026-09-19": 3600}

	service.rollDay(time.Date(2026, 9, 20, 8, 0, 0, 0, time.Local))

	if len(service.state.Activity.TodayApps) != 0 {
		t.Fatalf("TodayApps was not reset on day change: %#v", service.state.Activity.TodayApps)
	}
	if service.state.Activity.TodayAppsDay != "2026-09-20" {
		t.Fatalf("TodayAppsDay = %q, want 2026-09-20", service.state.Activity.TodayAppsDay)
	}
	if service.state.Activity.UptimeByDay["2026-09-19"] != 3600 {
		t.Fatal("uptime history must survive the day rollover")
	}
}

func TestRollDayKeepsTodayAppsWithinSameDay(t *testing.T) {
	service := &Service{}
	service.state.Activity.TodayAppsDay = "2026-09-20"
	service.state.Activity.TodayApps = map[string]AppUsage{
		"firefox": {Name: "Firefox", Seconds: 300},
	}

	service.rollDay(time.Date(2026, 9, 20, 23, 0, 0, 0, time.Local))

	if service.state.Activity.TodayApps["firefox"].Seconds != 300 {
		t.Fatal("same-day rollDay must keep TodayApps")
	}
}

func TestRollDayTrimsUptimeByDayToLimit(t *testing.T) {
	service := &Service{}
	service.state.Activity.TodayAppsDay = "2026-09-20"
	service.state.Activity.UptimeByDay = map[string]float64{}
	for i := 0; i < uptimeDayLimit+10; i++ {
		key := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC).
			AddDate(0, 0, i).Format("2006-01-02")
		service.state.Activity.UptimeByDay[key] = float64(i)
	}

	service.rollDay(time.Date(2026, 9, 20, 8, 0, 0, 0, time.Local))

	if len(service.state.Activity.UptimeByDay) != uptimeDayLimit {
		t.Fatalf("UptimeByDay keys = %d, want %d",
			len(service.state.Activity.UptimeByDay), uptimeDayLimit)
	}
	// The newest keys must be the ones that survive the trim.
	newest := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC).
		AddDate(0, 0, uptimeDayLimit+9).Format("2006-01-02")
	if _, ok := service.state.Activity.UptimeByDay[newest]; !ok {
		t.Fatalf("newest key %q was trimmed", newest)
	}
	oldest := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC).Format("2006-01-02")
	if _, ok := service.state.Activity.UptimeByDay[oldest]; ok {
		t.Fatalf("oldest key %q survived the trim", oldest)
	}
}

func TestAcquireInstanceLockIsExclusive(t *testing.T) {
	socketPath := filepath.Join(t.TempDir(), "kos-data.sock")
	first, err := acquireInstanceLock(socketPath)
	if err != nil {
		t.Fatal(err)
	}

	second, err := acquireInstanceLock(socketPath)
	if err == nil {
		_ = second.Close()
		t.Fatal("second service instance acquired the same lock")
	}

	if err = first.Close(); err != nil {
		t.Fatal(err)
	}
	third, err := acquireInstanceLock(socketPath)
	if err != nil {
		t.Fatalf("lock was not released after close: %v", err)
	}
	_ = third.Close()
}

// Regression test for the "concurrent map iteration and map write" panic:
// activity.snapshot used to shallow-copy s.state.Activity and marshal the
// response after releasing s.mu, while settle/rollDay kept mutating the live
// TodayApps and UptimeByDay maps. The snapshot is now deep-copied under the
// lock via marshal+unmarshal, so racing writers must stay safe under -race.
func TestActivitySnapshotConcurrentWithSettle(t *testing.T) {
	service := &Service{last: time.Now()}
	service.state.Activity.TodayApps = map[string]AppUsage{
		"firefox": {Name: "Firefox", Seconds: 300},
	}
	service.state.Activity.UptimeByDay = map[string]float64{}
	service.state.Activity.Active = true
	service.state.Activity.ActiveApp = "firefox"
	service.state.Activity.TodayAppsDay = day(time.Now())

	deadline := time.Now().Add(300 * time.Millisecond)
	done := make(chan struct{})
	go func() {
		defer close(done)
		for time.Now().Before(deadline) {
			service.mu.Lock()
			service.settle(time.Now())
			service.state.Activity.TodayApps["writer"] = AppUsage{
				Name:    "Writer",
				Seconds: float64(time.Now().UnixNano() % 100),
			}
			service.state.Activity.UptimeByDay[day(time.Now())] += 0.5
			service.mu.Unlock()
		}
	}()

	for time.Now().Before(deadline) {
		response := service.handleRequest(DataRequest{
			Version:   1,
			RequestID: "race",
			Operation: "activity.snapshot",
		})
		if !response.OK {
			t.Fatalf("activity.snapshot failed: %#v", response.Error)
		}
		// The race used to fire here: the outer marshal iterated maps that
		// the writer goroutine was mutating.
		raw, err := json.Marshal(response)
		if err != nil {
			t.Fatalf("marshal response: %v", err)
		}
		var decoded struct {
			OK     bool `json:"ok"`
			Result struct {
				Activity struct {
					TodayApps   map[string]AppUsage `json:"todayApps"`
					UptimeByDay map[string]float64  `json:"uptimeByDay"`
				} `json:"activity"`
			} `json:"result"`
		}
		if err := json.Unmarshal(raw, &decoded); err != nil {
			t.Fatalf("snapshot payload is not the documented shape: %v", err)
		}
		if !decoded.OK || decoded.Result.Activity.TodayApps == nil {
			t.Fatalf("snapshot payload missing activity data: %s", raw)
		}
	}
	<-done
}

// Same race class for weather.snapshot: the shallow WeatherState copy shared
// the Locations backing array that setWeatherLocation mutates in place.
func TestWeatherSnapshotConcurrentWithLocationWrites(t *testing.T) {
	service := &Service{last: time.Now()}
	service.state.Weather.Locations = []WeatherLocation{
		{ID: "open-meteo:1", Name: "Berlin", Latitude: 52.5, Longitude: 13.4},
		{ID: "open-meteo:2", Name: "Paris", Latitude: 48.9, Longitude: 2.4},
	}
	service.state.Weather.Current = &WeatherCurrent{Time: "2026-09-20T12:00", Temperature: 21}
	service.state.Weather.Hourly = []WeatherHourlyPoint{
		{Time: "2026-09-20T13:00", Temperature: 22},
	}
	service.state.Weather.Daily = []WeatherDay{
		{Date: "2026-09-20", TemperatureMaximum: 24, TemperatureMinimum: 14},
	}

	deadline := time.Now().Add(300 * time.Millisecond)
	done := make(chan struct{})
	go func() {
		defer close(done)
		counter := 0
		for time.Now().Before(deadline) {
			counter++
			service.mu.Lock()
			// Mirror setWeatherLocation's in-place write into the shared
			// Locations backing array plus the wholesale slice/pointer swaps.
			service.state.Weather.Locations[0] = WeatherLocation{
				ID: "open-meteo:1", Name: "Berlin",
				Latitude: 52.5, Longitude: float64(counter),
			}
			service.state.Weather.Current = &WeatherCurrent{
				Time: "2026-09-20T12:00", Temperature: float64(counter),
			}
			service.state.Weather.Hourly = append(service.state.Weather.Hourly[:1],
				WeatherHourlyPoint{Time: "x", Temperature: float64(counter)})
			service.mu.Unlock()
		}
	}()

	for time.Now().Before(deadline) {
		response := service.handleRequest(DataRequest{
			Version:   1,
			RequestID: "race",
			Operation: "weather.snapshot",
		})
		if !response.OK {
			t.Fatalf("weather.snapshot failed: %#v", response.Error)
		}
		raw, err := json.Marshal(response)
		if err != nil {
			t.Fatalf("marshal response: %v", err)
		}
		var decoded struct {
			OK     bool `json:"ok"`
			Result struct {
				Weather struct {
					Locations []WeatherLocation `json:"locations"`
				} `json:"weather"`
			} `json:"result"`
		}
		if err := json.Unmarshal(raw, &decoded); err != nil {
			t.Fatalf("snapshot payload is not the documented shape: %v", err)
		}
		if !decoded.OK || len(decoded.Result.Weather.Locations) != 2 {
			t.Fatalf("snapshot payload missing weather data: %s", raw)
		}
	}
	<-done
}

// Regression test for the JSONL interleave/deadlock class: broadcasts and
// request-response writes share each conn, and before per-conn write mutexes
// their bytes could interleave mid-line while racing deadline ops could arm
// (or clear) a deadline under another writer. Now every writer goes through
// writeLine, so each line the client reads must be exactly one JSON value.
func TestBroadcastDoesNotInterleaveWithResponses(t *testing.T) {
	service := &Service{desktopSubscribers: map[*subscriberConn]struct{}{}}
	server, client := net.Pipe()
	defer server.Close()
	defer client.Close()

	const broadcasts, responses = 30, 30

	readDone := make(chan error, 1)
	go func() {
		reader := bufio.NewReader(client)
		// One subscribe announcement + all broadcasts + all responses.
		for i := 0; i < 1+broadcasts+responses; i++ {
			line, err := reader.ReadBytes('\n')
			if err != nil {
				readDone <- err
				return
			}
			var value map[string]interface{}
			if err := json.Unmarshal(line, &value); err != nil {
				readDone <- err
				return
			}
		}
		readDone <- nil
	}()

	conn := &subscriberConn{Conn: server}
	service.subscribeDesktop(conn)
	defer service.unsubscribeDesktop(conn)

	var wg sync.WaitGroup
	wg.Add(2)
	go func() {
		defer wg.Done()
		for i := 0; i < broadcasts; i++ {
			service.publishDesktop()
		}
	}()
	go func() {
		defer wg.Done()
		for i := 0; i < responses; i++ {
			response, _ := json.Marshal(DataResponse{Version: 1, OK: true})
			if err := conn.writeLine(append(response, '\n'), 2*time.Second); err != nil {
				t.Errorf("response write failed: %v", err)
				return
			}
		}
	}()
	wg.Wait()

	select {
	case err := <-readDone:
		if err != nil {
			t.Fatalf("client read an interleaved/corrupt line: %v", err)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("timed out reading broadcast/response lines")
	}
}

// A subscriber that never reads must not stall publishes: the write deadline
// bounds each broadcast write and the conn is dropped after it expires, so
// publishDesktop returns quickly instead of blocking the event system.
func TestPublishDesktopDoesNotBlockOnUnreadConn(t *testing.T) {
	service := &Service{desktopSubscribers: map[*subscriberConn]struct{}{}}
	server, client := net.Pipe()
	defer server.Close()
	defer client.Close()

	conn := &subscriberConn{Conn: server}
	// Never read on client: the subscribe announcement write itself blocks
	// until the deadline, so it must run off the test goroutine.
	subscribed := make(chan struct{})
	go func() {
		service.subscribeDesktop(conn)
		close(subscribed)
	}()
	defer service.unsubscribeDesktop(conn)
	// Never read on client: every write blocks until the 100ms deadline,
	// so the conn is removed after the first publish and later publishes
	// have no subscribers at all.
	start := time.Now()
	for i := 0; i < 3; i++ {
		service.publishDesktop()
	}
	if elapsed := time.Since(start); elapsed > time.Second {
		t.Fatalf("publishes took %v; a stalled subscriber must not block them", elapsed)
	}
	<-subscribed
}
