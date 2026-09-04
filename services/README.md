# Resident services

Long-running, non-UI processes live here. `data-service/` builds
`kos-data-service`, the Go owner of durable metrics, activity history, and
desktop snapshots. Live desktop integration belongs to the separate C++
`platform/` service. Both services expose versioned JSONL sockets documented in
`shared/contracts/`.

The data service is started by `kos-data.service`; use `./tools/kosctl` from
the repository root for build, install, start, and uninstall operations. Check
it with `systemctl --user status kos-data.service` and follow logs with
`journalctl --user -u kos-data.service -f`.
