package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"sync"
	"testing"
	"time"
)

func desktopTestService(t *testing.T) *Service {
	t.Helper()
	root := t.TempDir()
	directory := filepath.Join(root, "Desktop")
	if err := os.Mkdir(directory, 0700); err != nil {
		t.Fatal(err)
	}
	s := &Service{desktopDirectory: directory, last: time.Now(),
		statePath: filepath.Join(root, "state.json"), snapshotPath: filepath.Join(root, "snapshot.json"),
		desktopSubscribers: map[*subscriberConn]struct{}{}}
	s.state.Activity.TodayApps = map[string]AppUsage{}
	s.state.Activity.TodayAppsDay = day(time.Now())
	s.state.Activity.UptimeByDay = map[string]float64{}
	return s
}

func desktopRequest(operation string, payload map[string]interface{}) DataRequest {
	return DataRequest{Version: 1, RequestID: "desktop-test", Operation: operation, Payload: payload}
}

func desktopOutputsRequest(outputs ...string) DataRequest {
	names := make([]interface{}, len(outputs))
	for i, name := range outputs {
		names[i] = name
	}
	defaultOutput := ""
	if len(outputs) > 0 {
		defaultOutput = outputs[0]
	}
	return desktopRequest("desktop.outputs", map[string]interface{}{"outputs": names, "defaultOutput": defaultOutput})
}

func desktopPlaceRequest(output string, paths ...string) DataRequest {
	values := make([]interface{}, len(paths))
	for i, path := range paths {
		values[i] = path
	}
	return desktopRequest("desktop.place", map[string]interface{}{"paths": values, "output": output})
}

func requireDesktopOK(t *testing.T, s *Service, request DataRequest) {
	t.Helper()
	if response := s.handleRequest(request); !response.OK {
		t.Fatalf("%s: %#v", request.Operation, response.Error)
	}
}

func desktopTestFile(t *testing.T, s *Service, name string) string {
	t.Helper()
	path := filepath.Join(s.desktopDirectory, name)
	if err := os.WriteFile(path, []byte("fixture"), 0600); err != nil {
		t.Fatal(err)
	}
	return path
}

func requireDesktopOwner(t *testing.T, s *Service, path, output string) {
	t.Helper()
	for _, entry := range s.state.Desktop.Entries {
		if entry.Path == path {
			if entry.Output != output {
				t.Fatalf("%s belongs to %q, want %q", filepath.Base(path), entry.Output, output)
			}
			return
		}
	}
	t.Fatalf("entry %s missing", path)
}

func TestDesktopFilesAndLaunchersHaveOnePersistentOwner(t *testing.T) {
	s := desktopTestService(t)
	file := desktopTestFile(t, s, "说明.txt")
	launcher := desktopTestFile(t, s, "Application.desktop")
	// Files may be discovered before the shell reports any real outputs.
	s.refreshDesktop()
	requireDesktopOwner(t, s, file, "")
	requireDesktopOK(t, s, desktopOutputsRequest("Panel-A", "Projector-B"))
	requireDesktopOwner(t, s, file, "Panel-A")
	requireDesktopOwner(t, s, launcher, "Panel-A")
	requireDesktopOK(t, s, desktopPlaceRequest("Projector-B", file, launcher))
	requireDesktopOwner(t, s, file, "Projector-B")
	requireDesktopOwner(t, s, launcher, "Projector-B")
	files, err := os.ReadDir(s.desktopDirectory)
	if err != nil || len(files) != 2 {
		t.Fatalf("placement must not copy files: %v, %v", files, err)
	}
	// Simulate a data-service restart with the persisted state, then connect
	// only one screen. Ownership is retained for the shell's fallback display.
	raw, err := os.ReadFile(s.statePath)
	if err != nil {
		t.Fatal(err)
	}
	var restored State
	if err = json.Unmarshal(raw, &restored); err != nil {
		t.Fatal(err)
	}
	s.state = restored
	s.desktopOutputs = nil
	s.defaultDesktopOutput = ""
	requireDesktopOK(t, s, desktopOutputsRequest("Panel-A"))
	requireDesktopOwner(t, s, file, "Projector-B")
	newFile := desktopTestFile(t, s, "added-while-disconnected.txt")
	s.refreshDesktop()
	requireDesktopOwner(t, s, newFile, "Panel-A")
	requireDesktopOK(t, s, desktopOutputsRequest("Projector-B", "Panel-A"))
	requireDesktopOwner(t, s, file, "Projector-B")
	requireDesktopOwner(t, s, newFile, "Panel-A")
	requireDesktopOK(t, s, desktopOutputsRequest())
	requireDesktopOwner(t, s, file, "Projector-B")
}

func TestDesktopRenameAndAtomicSavePreserveScreen(t *testing.T) {
	s := desktopTestService(t)
	requireDesktopOK(t, s, desktopOutputsRequest("Panel-A", "Panel-B"))
	path := desktopTestFile(t, s, "before.txt")
	requireDesktopOK(t, s, desktopPlaceRequest("Panel-B", path))
	renamed := filepath.Join(s.desktopDirectory, "renamed.txt")
	if err := os.Rename(path, renamed); err != nil {
		t.Fatal(err)
	}
	s.refreshDesktop()
	requireDesktopOwner(t, s, renamed, "Panel-B")
	if _, exists := s.state.DesktopPlacements[path]; exists {
		t.Fatal("old rename key survived reconciliation")
	}
	temp := desktopTestFile(t, s, ".editor-save")
	if err := os.Rename(temp, renamed); err != nil {
		t.Fatal(err)
	}
	s.refreshDesktop()
	requireDesktopOwner(t, s, renamed, "Panel-B")
	if err := os.Remove(renamed); err != nil {
		t.Fatal(err)
	}
	s.refreshDesktop()
	if len(s.state.Desktop.Entries) != 0 || len(s.state.DesktopPlacements) != 0 {
		t.Fatal("deleted entries retained ownership")
	}
}

func TestDesktopHardLinkDoesNotInheritAnotherIconScreen(t *testing.T) {
	s := desktopTestService(t)
	requireDesktopOK(t, s, desktopOutputsRequest("Panel-A", "Panel-B"))
	path := desktopTestFile(t, s, "first.txt")
	requireDesktopOK(t, s, desktopPlaceRequest("Panel-B", path))
	link := filepath.Join(s.desktopDirectory, "second.txt")
	if err := os.Link(path, link); err != nil {
		t.Fatal(err)
	}
	s.refreshDesktop()
	requireDesktopOwner(t, s, path, "Panel-B")
	requireDesktopOwner(t, s, link, "Panel-A")
}

func TestUnavailableDesktopDoesNotEraseAssignments(t *testing.T) {
	s := desktopTestService(t)
	requireDesktopOK(t, s, desktopOutputsRequest("Panel-A", "Panel-B"))
	path := desktopTestFile(t, s, "file.txt")
	requireDesktopOK(t, s, desktopPlaceRequest("Panel-B", path))
	directory := s.desktopDirectory
	s.desktopDirectory = filepath.Join(directory, "unavailable")
	if s.refreshDesktop() {
		t.Fatal("failed scan should retain the last complete snapshot")
	}
	s.desktopDirectory = directory
	requireDesktopOwner(t, s, path, "Panel-B")
	if s.refreshDesktop() {
		t.Fatal("unchanged desktop should not churn the snapshot")
	}
}

func TestDesktopPlacementRejectsStaleOrOutsideTargetsAtomically(t *testing.T) {
	s := desktopTestService(t)
	requireDesktopOK(t, s, desktopOutputsRequest("Panel-A", "Panel-B"))
	path := desktopTestFile(t, s, "file.txt")
	s.refreshDesktop()
	for _, request := range []DataRequest{
		desktopPlaceRequest("disconnected", path),
		desktopPlaceRequest("Panel-B", path, filepath.Join(s.desktopDirectory, "missing.txt")),
		desktopPlaceRequest("Panel-B", path, filepath.Join(filepath.Dir(s.desktopDirectory), "outside.txt")),
		desktopPlaceRequest("Panel-B", path, s.desktopDirectory+"/../outside.txt"),
		desktopOutputsRequest("Panel-A", "Panel-A"),
	} {
		if response := s.handleRequest(request); response.OK {
			t.Fatalf("invalid request accepted: %#v", request)
		}
		requireDesktopOwner(t, s, path, "Panel-A")
	}
}

func TestDesktopPlacementPersistsWithoutReplacingOtherState(t *testing.T) {
	s := desktopTestService(t)
	s.state.Activity.TodayApps["example"] = AppUsage{Name: "Example", Seconds: 321}
	s.state.Metrics.History = []MetricSample{{At: 123, CPU: 0.5}}
	requireDesktopOK(t, s, desktopOutputsRequest("Panel-A"))
	path := desktopTestFile(t, s, "file.txt")
	requireDesktopOK(t, s, desktopPlaceRequest("Panel-A", path))
	raw, err := os.ReadFile(s.statePath)
	if err != nil {
		t.Fatal(err)
	}
	var state State
	if err := json.Unmarshal(raw, &state); err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(state.Metrics.History, s.state.Metrics.History) || state.Activity.TodayApps["example"].Seconds != 321 {
		t.Fatal("desktop update overwrote telemetry or activity")
	}
}

func TestDesktopPlacementConcurrentScanAndSnapshot(t *testing.T) {
	s := desktopTestService(t)
	requireDesktopOK(t, s, desktopOutputsRequest("Panel-A", "Panel-B"))
	path := desktopTestFile(t, s, "file.txt")
	s.refreshDesktop()
	var workers sync.WaitGroup
	for i := 0; i < 3; i++ {
		workers.Add(1)
		go func(worker int) {
			defer workers.Done()
			for j := 0; j < 12; j++ {
				switch worker {
				case 0:
					s.refreshDesktop()
				case 1:
					response := s.handleRequest(desktopPlaceRequest([]string{"Panel-A", "Panel-B"}[j%2], path))
					if !response.OK {
						t.Errorf("placement failed: %#v", response.Error)
					}
				case 2:
					response := s.handleRequest(desktopRequest("desktop.snapshot", nil))
					if _, err := json.Marshal(response); err != nil {
						t.Error(err)
					}
				}
			}
		}(i)
	}
	workers.Wait()
	requireDesktopOwner(t, s, path, "Panel-B")
}
