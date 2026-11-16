# Data service architecture

`services/data-service` builds one Go executable from one `main` package.
Files separate responsibilities; package boundaries, goroutine ownership,
JSON field names and the versioned Socket protocol remain unchanged.
The JSONL envelope, state roots and operations are documented below.

| File | Responsibility |
| --- | --- |
| `main.go` | Instance lock, startup sequence and periodic scheduling |
| `service.go` | Shared `Service` ownership, defaults and state restoration |
| `types.go` | Persisted state and snapshot value types with JSON tags |
| `metrics.go` | CPU, memory, disk, frequency and temperature sampling |
| `activity.go` | Activity attribution, daily rollover and journal history |
| `desktop.go` | Desktop directory snapshots, reconciliation and filesystem watching |
| `desktop_placement.go` | Desktop screen assignment and placement persistence |
| `weather.go` | Weather provider, refresh policy and normalized weather state |
| `persistence.go` | Serialized, atomic state and snapshot writes |
| `subscriptions.go` | Subscriber lifetime, serialized JSONL writes and event publication |
| `protocol.go` | Request/response/error envelopes, operation dispatch and Socket serving |

## State and concurrency contracts

`Service.mu` protects mutable state and snapshot reads. Sampling reads procfs
and sysfs outside that lock, then publishes a coherent update under it. The
main scheduler owns CPU counter history and periodic sampling. Activity
settlement and day rollover remain under the same state ownership as before.

`persistMu` serializes persisted generations, while `desktopMu` serializes
directory refresh and placement changes. Subscriber membership has its own
mutex; each `subscriberConn` serializes response and event writes so concurrent
publishers cannot interleave JSONL bytes. File boundaries do not introduce new
goroutines, locks, callbacks or a second copy of state.

`main.go` still samples and publishes the initial desktop snapshot before
accepting clients. Feature code works with the shared typed state; only the
protocol and subscription layer marshals transport envelopes. Existing tests
cover concurrent snapshots and placement, subscriber framing, atomic writes,
daily activity, sensor selection and weather fallback. Run the data layer
through `tools/run-tests.sh`; Go's race detector can additionally check the
same package's concurrent tests in the verification environment.

## State and sockets

State remains at:

```text
$XDG_STATE_HOME/quickshell/shell-data-service/state.json
$XDG_STATE_HOME/quickshell/shell-data-service/snapshot.json
```

The runtime API is:

```text
$XDG_RUNTIME_DIR/kos-data.sock
```

The socket is mode `0600`. Requests are versioned JSON Lines:

```json
{"version":1,"requestId":"42","operation":"metrics.snapshot","payload":{}}
{"version":1,"requestId":"42","ok":true,"result":{"metrics":{}}}
```

Supported operations are:

- `metrics.snapshot`;
- `activity.snapshot` and `activity.active-app`;
- `desktop.snapshot`, `desktop.refresh`, `desktop.outputs` and `desktop.place`;
- `weather.snapshot`, `weather.search`, `weather.refresh`,
  `weather.set-location`, `weather.remove-location`, and `weather.set-units`.

Desktop changes are pushed as `desktop.changed` events after a complete
directory scan has been persisted. A completed weather state transition is
pushed as `weather.changed`; clients then request `weather.snapshot`, so every
response uses the same versioned envelope and request correlation.

Example weather requests:

```json
{"version":1,"requestId":"w1","operation":"weather.search","payload":{"query":"Changsha","language":"en","limit":8}}
{"version":1,"requestId":"w2","operation":"weather.set-units","payload":{"units":"metric"}}
```

The weather payload itself follows
[`shared/contracts/weather-v1.schema.json`](../shared/contracts/weather-v1.schema.json).
The service requests at most 48 hourly and seven daily points, refreshes after
one hour, and marks data stale after two hours. Failed refreshes preserve the
last complete forecast and expose the error alongside it.


## Operations

Build/install/restart and verification run only in the VM or CI; see [Development](Development.md).
`kosctl uninstall` preserves the data state directory. Set `GOPROXY` to a reachable proxy or `off`
for a populated offline cache if the default module proxy is unavailable.
