# Resident services

Long-running, non-UI processes live here. `data-service/` builds
`kos-data-service`, the Go owner of durable metrics, activity history, desktop
snapshots, and the shared weather cache. Live desktop integration belongs to the separate C++
`platform/` service. Both services expose versioned JSONL sockets documented in
`shared/contracts/`.

`pim-service/` builds `kos-pim-service`, the D-Bus owner of calendar, task,
reminder, and widget snapshot state. Its activation and persistence contracts
are described in [PimArchitecture](../docs/PimArchitecture.md).

`ai/` supplies the optional `kos-ai-worker` used by the platform service for
spatial wallpaper preparation. It is a subprocess worker rather than a
resident systemd service; see [DepthEngine](../docs/DepthEngine.md).

The data service is started by `kos-data.service`; use `./tools/kosctl` from
the repository root for build, install, start, and uninstall operations. Check
it with `systemctl --user status kos-data.service` and follow logs with
`journalctl --user -u kos-data.service -f`.
