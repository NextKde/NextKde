package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"time"
)

func writeJSONBytes(path string, raw []byte) error {
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		return err
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, raw, 0644); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

// persist marshals state.json and snapshot.json under s.mu — the same
// sanctioned pattern as snapshotResult — so the encoder never iterates maps
// or slices that concurrent writers mutate, then performs the actual disk
// writes after releasing the lock so no blocking IO stalls state updates.
func (s *Service) persist() {
	// Serialize snapshot capture and both renames. Concurrent callers otherwise
	// share the same .tmp paths and may overwrite newer state with an older copy.
	s.persistMu.Lock()
	defer s.persistMu.Unlock()
	s.mu.Lock()
	s.settle(time.Now())
	snapshot := Snapshot{
		SchemaVersion: 1,
		GeneratedAt:   time.Now().UnixMilli(),
		Metrics:       s.state.Metrics,
		Activity:      s.state.Activity,
		Desktop:       s.state.Desktop,
		Weather:       s.state.Weather,
	}
	stateRaw, stateErr := json.Marshal(s.state)
	snapshotRaw, snapshotErr := json.Marshal(snapshot)
	s.mu.Unlock()
	if stateErr == nil {
		_ = writeJSONBytes(s.statePath, stateRaw)
	}
	// snapshot.json stays written for backward compatibility: the external
	// kos-weather app reads it as its offline fallback.
	if snapshotErr == nil {
		_ = writeJSONBytes(s.snapshotPath, snapshotRaw)
	}
}
