package main

import (
	"bufio"
	"fmt"
	"github.com/fsnotify/fsnotify"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"sort"
	"strings"
	"time"
)

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

func readDesktop(directory string) (Desktop, error) {
	desktop := Desktop{Directory: directory, Entries: []DesktopEntry{}}
	entries, err := os.ReadDir(directory)
	if err != nil {
		return desktop, err
	}
	for _, entry := range entries {
		// Match standard desktop behaviour: dot-files are managed by their
		// owning applications and do not appear as desktop icons by default.
		if strings.HasPrefix(entry.Name(), ".") {
			continue
		}
		info, err := entry.Info()
		if err != nil {
			// A rename racing the scan can invalidate one directory entry.
			// Discard the partial scan so its old identity survives until the
			// next complete snapshot can associate the new name with it.
			return desktop, err
		}
		kind := desktopKind(entry)
		title, icon := "", ""
		if kind == "launcher" {
			title, icon = desktopLauncherPresentation(filepath.Join(directory, entry.Name()))
		}
		desktop.Entries = append(desktop.Entries, DesktopEntry{
			Name: entry.Name(), Path: filepath.Join(directory, entry.Name()),
			Title: title, Kind: kind, Icon: icon, ModifiedAt: info.ModTime().UnixMilli(),
			fileID: desktopFileID(info),
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
	return desktop, nil
}

func (s *Service) refreshDesktop() bool {
	s.desktopMu.Lock()
	defer s.desktopMu.Unlock()
	return s.refreshDesktopLocked()
}

// desktopMu serializes scans with output assignments so an older watcher scan
// cannot overwrite a placement made just after a create, rename, or drop.
func (s *Service) refreshDesktopLocked() bool {
	desktop, err := readDesktop(s.desktopDirectory)
	if err != nil {
		// A temporarily unavailable directory is not an empty desktop. Keep its
		// ownership records so reconnecting storage does not lose placements.
		return false
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	placements := reconcileDesktopPlacements(&desktop, s.state.DesktopPlacements, s.defaultDesktopOutput)
	previous := s.state.Desktop
	// The update time is intentionally excluded: unchanged directory scans do
	// not churn the atomic snapshot or wake the QML consumer.
	previous.UpdatedAt = 0
	comparison := desktop
	comparison.UpdatedAt = 0
	if reflect.DeepEqual(previous, comparison) && reflect.DeepEqual(placements, s.state.DesktopPlacements) {
		return false
	}
	s.state.Desktop = desktop
	s.state.DesktopPlacements = placements
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
