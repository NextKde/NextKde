package main

import (
	"bufio"
	"encoding/json"
	"net"
	"os"
	"path/filepath"
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
	service := &Service{desktopSubscribers: map[net.Conn]struct{}{}}
	server, client := net.Pipe()
	defer server.Close()
	defer client.Close()

	done := make(chan struct{})
	go func() {
		service.subscribeDesktop(server)
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
