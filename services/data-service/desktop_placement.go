package main

import (
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"syscall"
	"time"
)

// Persist ownership independently from the transient set of connected outputs.
// File identity carries ownership through renames; keeping the path as the key
// also preserves it when editors atomically replace a file's contents.
type DesktopPlacement struct {
	Output string `json:"output"`
	FileID string `json:"fileId,omitempty"`
}

func desktopFileID(info os.FileInfo) string {
	if stat, ok := info.Sys().(*syscall.Stat_t); ok {
		return fmt.Sprintf("%d:%d", stat.Dev, stat.Ino)
	}
	return ""
}

func reconcileDesktopPlacements(desktop *Desktop, previous map[string]DesktopPlacement, defaultOutput string) map[string]DesktopPlacement {
	currentPaths := make(map[string]bool, len(desktop.Entries))
	currentIDs := make(map[string]int, len(desktop.Entries))
	for _, entry := range desktop.Entries {
		currentPaths[entry.Path] = true
		currentIDs[entry.fileID]++
	}
	// Only a unique identity may be followed across a rename. Hard links must
	// not borrow another still-existing icon's screen assignment.
	oldIDs := make(map[string]int, len(previous))
	renamed := make(map[string]DesktopPlacement, len(previous))
	for path, placement := range previous {
		oldIDs[placement.FileID]++
		if !currentPaths[path] {
			renamed[placement.FileID] = placement
		}
	}
	next := make(map[string]DesktopPlacement, len(desktop.Entries))
	for i := range desktop.Entries {
		entry := &desktop.Entries[i]
		placement, exists := previous[entry.Path]
		if !exists && entry.fileID != "" && oldIDs[entry.fileID] == 1 && currentIDs[entry.fileID] == 1 {
			placement = renamed[entry.fileID]
		}
		if placement.Output == "" {
			placement.Output = defaultOutput
		}
		placement.FileID = entry.fileID
		next[entry.Path] = placement
		entry.Output = placement.Output
	}
	return next
}

func validDesktopOutput(output string) bool {
	return output != "" && len(output) <= 256 && strings.TrimSpace(output) == output &&
		!strings.ContainsAny(output, "\x00\r\n")
}

func (s *Service) configureDesktopOutputs(request DataRequest) DataResponse {
	rawOutputs, ok := request.Payload["outputs"].([]interface{})
	defaultOutput, _ := request.Payload["defaultOutput"].(string)
	if !ok || len(rawOutputs) > 64 {
		return dataError(request, "invalid-desktop-outputs", "显示器列表无效", false)
	}
	outputs := make([]string, 0, len(rawOutputs))
	for _, raw := range rawOutputs {
		output, ok := raw.(string)
		if !ok || !validDesktopOutput(output) || slices.Contains(outputs, output) {
			return dataError(request, "invalid-desktop-outputs", "显示器列表无效", false)
		}
		outputs = append(outputs, output)
	}
	if (len(outputs) == 0 && defaultOutput != "") || (len(outputs) > 0 && !slices.Contains(outputs, defaultOutput)) {
		return dataError(request, "invalid-desktop-outputs", "默认显示器不可用", false)
	}
	s.desktopMu.Lock()
	s.desktopOutputs = outputs
	s.defaultDesktopOutput = defaultOutput
	changed := s.refreshDesktopLocked()
	s.desktopMu.Unlock()
	if changed {
		s.persist()
		s.publishDesktop()
	}
	return s.desktopResponse(request)
}

func (s *Service) desktopResponse(request DataRequest) DataResponse {
	s.mu.Lock()
	desktop := s.state.Desktop
	s.mu.Unlock()
	return DataResponse{Version: 1, RequestID: request.RequestID, OK: true,
		Result: map[string]interface{}{"desktop": desktop}}
}

func (s *Service) placeDesktopEntries(request DataRequest) DataResponse {
	rawPaths, ok := request.Payload["paths"].([]interface{})
	output, _ := request.Payload["output"].(string)
	if !ok || len(rawPaths) == 0 || len(rawPaths) > 4096 || !validDesktopOutput(output) {
		return dataError(request, "invalid-desktop-placement", "桌面图标归属请求无效", false)
	}
	paths := make(map[string]bool, len(rawPaths))
	for _, raw := range rawPaths {
		path, ok := raw.(string)
		if !ok || len(path) > 4096 || !filepath.IsAbs(path) || filepath.Clean(path) != path ||
			filepath.Dir(path) != filepath.Clean(s.desktopDirectory) || strings.HasPrefix(filepath.Base(path), ".") {
			return dataError(request, "invalid-desktop-placement", "只能分配桌面目录中的图标", false)
		}
		paths[path] = true
	}
	s.desktopMu.Lock()
	if !slices.Contains(s.desktopOutputs, output) {
		s.desktopMu.Unlock()
		return dataError(request, "desktop-output-unavailable", "目标显示器已断开，请重试", true)
	}
	for path := range paths {
		if _, err := os.Lstat(path); err != nil {
			s.desktopMu.Unlock()
			return dataError(request, "desktop-entry-unavailable", "桌面文件已移动或删除，请重试", true)
		}
	}
	changed := s.refreshDesktopLocked()
	s.mu.Lock()
	found := 0
	for _, entry := range s.state.Desktop.Entries {
		if paths[entry.Path] {
			found++
		}
	}
	if found != len(paths) {
		s.mu.Unlock()
		s.desktopMu.Unlock()
		if changed {
			s.persist()
			s.publishDesktop()
		}
		return dataError(request, "desktop-entry-unavailable", "桌面文件已移动或删除，请重试", true)
	}
	// Publish a fresh slice; readers may still be encoding a previous snapshot.
	desktop := s.state.Desktop
	desktop.Entries = slices.Clone(desktop.Entries)
	for i := range desktop.Entries {
		entry := &desktop.Entries[i]
		if paths[entry.Path] && entry.Output != output {
			entry.Output = output
			s.state.DesktopPlacements[entry.Path] = DesktopPlacement{Output: output, FileID: entry.fileID}
			changed = true
		}
	}
	if changed {
		desktop.UpdatedAt = time.Now().UnixMilli()
		s.state.Desktop = desktop
	}
	s.mu.Unlock()
	s.desktopMu.Unlock()
	if changed {
		s.persist()
		s.publishDesktop()
	}
	return s.desktopResponse(request)
}
