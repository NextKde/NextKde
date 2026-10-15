# Data service architecture

`services/data-service` builds one Go executable from one `main` package.
Files separate responsibilities; package boundaries, goroutine ownership,
JSON field names and the versioned Socket protocol remain unchanged.
The JSONL envelope and operations are documented in
[Shell data service](ShellDataService.md#state-and-sockets).

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
