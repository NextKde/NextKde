// Delta each socket before grouping: closing a connection must not subtract
// its lifetime bytes from the surviving connections of the same application.
export function sample(previous, sockets, timestamp) {
    const next = Object.create(null);
    const groups = Object.create(null);
    for (const socket of sockets || []) {
        const key = String(socket.id) + ':' + socket.pid;
        if (next[key]) continue;
        const rx = Math.max(0, Number(socket.rxBytes) || 0);
        const tx = Math.max(0, Number(socket.txBytes) || 0);
        const old = previous[key];
        const elapsed = old ? (timestamp - old.timestamp) / 1000 : 0;
        next[key] = { rx, tx, timestamp };
        const name = String(socket.name || socket.pid);
        const app = groups[name] || {name, download: 0, upload: 0, processes: []};
        if (!app.processes.includes(socket.pid)) app.processes.push(socket.pid);
        if (old && elapsed > 0 && elapsed <= 5 && rx >= old.rx && tx >= old.tx) {
            app.download += (rx - old.rx) / elapsed;
            app.upload += (tx - old.tx) / elapsed;
        }
        groups[name] = app;
    }
    return {previous: next, rows: Object.values(groups).sort((a, b) =>
        (b.download + b.upload) - (a.download + a.upload) || a.name.localeCompare(b.name))};
}
