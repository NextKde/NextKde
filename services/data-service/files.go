package main

import (
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"
)

// A file index for the island's Finder.
//
// The original (Islet) shells out to `fd` and `fzf`. This shell may not run
// external commands from its UI, so the walk and the matching live here, in
// the service that already owns the desktop file listing. The index is a
// snapshot: it is rebuilt in the background every few minutes, and a search
// answers from whatever the last build produced.

const (
	// The walk stops here. A home directory can hold hundreds of thousands of
	// files, and an unbounded index is a memory problem for a feature that
	// only ever shows a screenful of results.
	fileIndexLimit = 40000
	// Deep trees are rarely what a person is looking for, and the walk is
	// what costs the most.
	fileIndexMaxDepth = 12
	// How often the index is rebuilt in the background.
	fileIndexRefresh = 10 * time.Minute
)

// Directories that are never worth indexing: build trees, caches and the
// version-control metadata that fills a source checkout.
var fileIndexSkipDirs = map[string]bool{
	"node_modules": true,
	"venv":         true,
	".venv":        true,
	"__pycache__":  true,
	"target":       true,
	"vendor":       true,
}

type fileEntry struct {
	Path  string `json:"path"`
	Name  string `json:"name"`
	Dir   string `json:"dir"`
	Mod   int64  `json:"mod"`
	IsDir bool   `json:"isDir"`
}

type fileIndex struct {
	mu      sync.RWMutex
	entries []fileEntry
	ready   bool
	updated time.Time
	// building guards the background rebuild so a burst of searches cannot
	// queue a rebuild each.
	building bool
}

func newFileIndex() *fileIndex {
	return &fileIndex{}
}

// buildFileIndex walks the home directory. Hidden entries are skipped
// entirely: a Finder that lists .config and .cache is noise, and the user
// asked for a file, not a directory tour.
func buildFileIndex(root string) []fileEntry {
	entries := make([]fileEntry, 0, 4096)
	rootDepth := strings.Count(filepath.Clean(root), string(os.PathSeparator))
	_ = filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if path == root {
			return nil
		}
		name := d.Name()
		if d.IsDir() {
			if fileIndexSkipDirs[name] || strings.HasPrefix(name, ".") {
				return filepath.SkipDir
			}
			if strings.Count(filepath.Clean(path), string(os.PathSeparator))-rootDepth > fileIndexMaxDepth {
				return filepath.SkipDir
			}
			return nil
		}
		if strings.HasPrefix(name, ".") {
			return nil
		}
		info, err := d.Info()
		if err != nil {
			return nil
		}
		entries = append(entries, fileEntry{
			Path: path,
			Name: name,
			Dir:  filepath.Dir(path),
			Mod:  info.ModTime().UnixMilli(),
		})
		if len(entries) >= fileIndexLimit {
			return filepath.SkipAll
		}
		return nil
	})
	return entries
}

// fuzzyScore matches a query against a name as a subsequence. Consecutive
// hits and hits at a word boundary score higher, which is enough to put
// "notes.md" above "n/o/t/e/s/other.md" for the query "notes".
func fuzzyScore(query, target string) (int, bool) {
	q := []rune(strings.ToLower(query))
	t := []rune(strings.ToLower(target))
	if len(q) == 0 {
		return 1, true
	}
	score := 0
	at := 0
	streak := 0
	for _, r := range q {
		found := -1
		for i := at; i < len(t); i++ {
			if t[i] == r {
				found = i
				break
			}
		}
		if found < 0 {
			return 0, false
		}
		if found == at && at > 0 {
			streak++
		} else {
			streak = 0
		}
		score += 10 + streak*6
		if found == 0 || (found > 0 && isWordBreak(t[found-1])) {
			score += 14
		}
		at = found + 1
	}
	// A short name that matched is a better answer than a long one.
	score += 60 - len(t)/3
	return score, true
}

func isWordBreak(r rune) bool {
	switch r {
	case ' ', '-', '_', '/', '.', '\\':
		return true
	}
	return false
}

// resolveFile finds where a shelved file went.
//
// A shelf keeps a reference, not a copy, so the file can be moved or renamed
// behind the shelf's back. The original path is checked first; if it is gone,
// the index is searched for the same name, and the most recent match wins.
func (s *Service) resolveFile(path, name string) (string, bool) {
	if path != "" {
		if info, err := os.Stat(path); err == nil && !info.IsDir() {
			return path, true
		}
	}
	if name == "" {
		return path, false
	}
	s.files.mu.RLock()
	entries := s.files.entries
	ready := s.files.ready
	s.files.mu.RUnlock()
	if !ready {
		s.refreshFileIndex()
		s.files.mu.RLock()
		entries = s.files.entries
		s.files.mu.RUnlock()
	}
	best := ""
	bestMod := int64(0)
	for _, entry := range entries {
		if entry.Name != name {
			continue
		}
		if best == "" || entry.Mod > bestMod {
			best = entry.Path
			bestMod = entry.Mod
		}
	}
	if best == "" {
		return path, false
	}
	return best, true
}

// searchFiles answers a query from the current index. An empty query returns
// the most recently touched files, which is what the Finder shows before you
// type anything.
func (s *Service) searchFiles(query string, limit int) ([]fileEntry, int, bool) {
	if limit <= 0 {
		limit = 20
	}
	if limit > 100 {
		limit = 100
	}
	s.files.mu.RLock()
	entries := s.files.entries
	ready := s.files.ready
	s.files.mu.RUnlock()
	if !ready {
		s.refreshFileIndex()
		s.files.mu.RLock()
		entries = s.files.entries
		ready = s.files.ready
		s.files.mu.RUnlock()
	}

	type scored struct {
		entry fileEntry
		score int
	}
	matches := make([]scored, 0, 64)
	for _, entry := range entries {
		if strings.TrimSpace(query) == "" {
			matches = append(matches, scored{entry: entry, score: 0})
			continue
		}
		score, ok := fuzzyScore(query, entry.Name)
		if !ok {
			continue
		}
		matches = append(matches, scored{entry: entry, score: score})
	}
	if strings.TrimSpace(query) == "" {
		sort.Slice(matches, func(i, j int) bool {
			return matches[i].entry.Mod > matches[j].entry.Mod
		})
	} else {
		sort.SliceStable(matches, func(i, j int) bool {
			if matches[i].score != matches[j].score {
				return matches[i].score > matches[j].score
			}
			return matches[i].entry.Mod > matches[j].entry.Mod
		})
	}
	if len(matches) > limit {
		matches = matches[:limit]
	}
	results := make([]fileEntry, 0, len(matches))
	for _, match := range matches {
		results = append(results, match.entry)
	}
	return results, len(entries), ready
}

// refreshFileIndex rebuilds the index. It runs on the calling goroutine when
// the index is empty (the caller needs an answer now) and in the background
// otherwise.
func (s *Service) refreshFileIndex() {
	s.files.mu.Lock()
	if s.files.building {
		s.files.mu.Unlock()
		return
	}
	s.files.building = true
	s.files.mu.Unlock()

	home, err := os.UserHomeDir()
	if err != nil || home == "" {
		s.files.mu.Lock()
		s.files.building = false
		s.files.mu.Unlock()
		return
	}
	entries := buildFileIndex(home)
	s.files.mu.Lock()
	s.files.entries = entries
	s.files.ready = true
	s.files.updated = time.Now()
	s.files.building = false
	s.files.mu.Unlock()
}

// startFileIndexRefresh keeps the index warm in the background, the way the
// original refreshes its file list every ten minutes.
func (s *Service) startFileIndexRefresh() {
	go func() {
		ticker := time.NewTicker(fileIndexRefresh)
		defer ticker.Stop()
		for range ticker.C {
			s.files.mu.RLock()
			building := s.files.building
			s.files.mu.RUnlock()
			if building {
				continue
			}
			s.refreshFileIndex()
		}
	}()
}
