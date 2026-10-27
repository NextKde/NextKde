// kos-data-service starts the persistent telemetry service and owns its instance lock.
package main

import (
	"errors"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"time"

	"golang.org/x/sys/unix"
)

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
	// The island's Finder answers from an index of the home directory. It is
	// built in the background so the first search does not have to walk the
	// whole tree while the user is typing.
	s.startFileIndexRefresh()
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
	// Settle attribution every second; persistence still runs every ten seconds,
	// so a crash can lose edits since the last successful disk write.
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
