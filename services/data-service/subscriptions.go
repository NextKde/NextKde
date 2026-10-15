package main

import (
	"encoding/json"
	"net"
	"sync"
	"time"
)

// subscriberConn serializes every write to a shared JSONL connection. All
// three writers (subscribe announcement, broadcasts, request responses) go
// through writeLine, which holds wmu for the whole set-deadline -> write ->
// clear-deadline sequence so bytes can never interleave on the wire and no
// goroutine can clear a deadline another writer just armed.
type subscriberConn struct {
	net.Conn
	wmu sync.Mutex
}

// writeLine writes one complete JSONL line under a bounded deadline. The
// deadline is always cleared afterwards because it is absolute: leaving it
// armed would make every later write on the long-lived connection time out
// (the bug that used to freeze the shell after its first metrics snapshot).
func (c *subscriberConn) writeLine(raw []byte, timeout time.Duration) error {
	c.wmu.Lock()
	defer c.wmu.Unlock()
	if err := c.SetWriteDeadline(time.Now().Add(timeout)); err != nil {
		return err
	}
	_, err := c.Write(raw)
	// Clear even on a failed write: a conn that stays in service must not
	// inherit a stale deadline, and a dead conn is removed anyway.
	_ = c.SetWriteDeadline(time.Time{})
	return err
}

// subscribeDesktop turns the existing local event socket into a small
// notification channel as well. QML keeps one connection open and only reads
// the snapshot after a change notification, so neither side polls a directory.
func (s *Service) subscribeDesktop(conn *subscriberConn) {
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
	// writeLine serializes this against broadcasts and responses on the same
	// connection and clears the absolute write deadline afterwards, so it
	// cannot leak into the long-lived request loop (the bug where the shell
	// only ever received its first metrics snapshot). A failed write is
	// ignored: the conn stays usable for the request loop.
	event := map[string]interface{}{"version": 1, "event": "desktop.changed",
		"payload": map[string]interface{}{"updatedAt": time.Now().UnixMilli()}}
	raw, _ := json.Marshal(event)
	_ = conn.writeLine(append(raw, '\n'), 100*time.Millisecond)
}

func (s *Service) unsubscribeDesktop(conn *subscriberConn) {
	s.desktopSubscribersMu.Lock()
	delete(s.desktopSubscribers, conn)
	s.desktopSubscribersMu.Unlock()
}

// broadcastEvent writes one JSONL event to every subscriber. The subscriber
// list is collected under desktopSubscribersMu, but the bounded writes run
// after releasing it, serialized per connection by each conn's wmu — so a
// slow subscriber can never hold the registry lock and deadlock every later
// publish or subscribe. Dead conns are removed and closed afterwards.
func (s *Service) broadcastEvent(name string) {
	event := map[string]interface{}{"version": 1, "event": name,
		"payload": map[string]interface{}{"updatedAt": time.Now().UnixMilli()}}
	raw, _ := json.Marshal(event)
	line := append(raw, '\n')

	s.desktopSubscribersMu.Lock()
	subscribers := make([]*subscriberConn, 0, len(s.desktopSubscribers))
	for conn := range s.desktopSubscribers {
		subscribers = append(subscribers, conn)
	}
	s.desktopSubscribersMu.Unlock()

	var dead []*subscriberConn
	for _, conn := range subscribers {
		if err := conn.writeLine(line, 100*time.Millisecond); err != nil {
			dead = append(dead, conn)
		}
	}
	if len(dead) > 0 {
		s.desktopSubscribersMu.Lock()
		for _, conn := range dead {
			delete(s.desktopSubscribers, conn)
		}
		s.desktopSubscribersMu.Unlock()
		for _, conn := range dead {
			_ = conn.Close()
		}
	}
}

func (s *Service) publishDesktop() {
	s.broadcastEvent("desktop.changed")
}

// Weather shares the connection registry with desktop events: both broadcast
// through broadcastEvent, and the per-connection wmu inside writeLine keeps
// two asynchronous broadcasts from interleaving on a JSONL connection.
func (s *Service) publishWeather() {
	s.broadcastEvent("weather.changed")
}
