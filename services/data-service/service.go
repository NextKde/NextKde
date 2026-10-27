package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sync"
	"time"
)

type Service struct {
	mu                      sync.Mutex
	persistMu               sync.Mutex
	desktopMu               sync.Mutex
	desktopOutputs          []string
	defaultDesktopOutput    string
	desktopSubscribersMu    sync.Mutex
	desktopSubscribers      map[*subscriberConn]struct{}
	state                   State
	statePath, snapshotPath string
	desktopDirectory        string
	weatherProvider         WeatherProvider
	// The file index behind the island's Finder. Islet shells out to `fd`
	// for this; the shell may not run external commands from its UI, so the
	// walk lives in the service.
	files                *fileIndex
	weatherRequestSerial uint64
	// weatherFailStreak counts consecutive forecast fetch failures and drives
	// the exponential retry backoff. Guarded by s.mu.
	weatherFailStreak int
	last              time.Time
	// prevCPUTotal/prevCPUIdle are only touched by readCPU, which runs only
	// from sample() (the main goroutine's startup call and 10s tick), so they
	// stay race-free even though sampling happens outside s.mu.
	prevCPUTotal, prevCPUIdle float64
	// sensors caches the one-time thermal/hwmon enumeration: sysfs device
	// topology and labels do not change at runtime, so only the input values
	// are re-read on every sample.
	sensorsOnce sync.Once
	sensors     []sensorProbe
}

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
		desktopSubscribers: map[*subscriberConn]struct{}{},
		weatherProvider:    newOpenMeteoProvider(),
		files:              newFileIndex(),
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
	// State written before the day boundary was tracked may carry rows from
	// many days in TodayApps and an unbounded uptime ledger.
	s.rollDay(time.Now())
	return s
}
