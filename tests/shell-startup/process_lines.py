#!/usr/bin/env python3
"""Drain subprocess output without mixing buffered readline with select()."""
import queue
import threading
import time


class ProcessLines:
    def __init__(self, process):
        self.events = queue.Queue()
        self.thread = threading.Thread(target=self._read, args=(process,), daemon=True)
        self.thread.start()

    def _read(self, process):
        for line in process.stdout:
            self.events.put((time.monotonic(), line))
        self.events.put((time.monotonic(), None))

    def get(self, timeout=.1):
        try:
            return self.events.get(timeout=timeout)
        except queue.Empty:
            return None
