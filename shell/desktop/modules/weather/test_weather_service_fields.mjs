import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { fileURLToPath } from "node:url"
import { dirname, join } from "node:path"

const here = dirname(fileURLToPath(import.meta.url))
const service = readFileSync(join(here, "WeatherService.qml"), "utf8")

// weather-v1 optional fields must stay exposed to shell consumers. Each
// display property is finite-gated and degrades to "" so old snapshots
// without the key never render placeholder noise.
for (const field of ["windGust", "uvIndex", "visibility", "moonPhase"]) {
    assert.match(service,
        new RegExp("readonly property string " + field +
            ": available && Number\\.isFinite\\(Number\\(current\\." + field + "\\)\\)"),
        "WeatherService exposes a finite-gated " + field + " display property")
}

// moonPhase maps through the same 8-name bucket the weather app uses.
assert.match(service, /function moonPhaseName\(phase\)/,
    "moonPhaseName maps a [0,1) phase to a name")
assert.match(service, /Math\.round\(\(\(phase % 1\) \+ 1\) % 1 \* 8\) % 8/,
    "moonPhaseName buckets by round(p*8) % 8")
for (const name of ["New Moon", "Waxing Crescent", "First Quarter", "Waxing Gibbous",
    "Full Moon", "Waning Gibbous", "Last Quarter", "Waning Crescent"]) {
    assert.ok(service.includes('"' + name + '"'), 'moonPhaseName covers "' + name + '"')
}

// Snapshot wiring must keep flowing into the service.
assert.match(service, /airQuality = weather\.airQuality \?\? null/,
    "applyWeather keeps wiring the airQuality object")
assert.match(service, /current = weather\.current \?\? null/,
    "applyWeather keeps wiring the current object")
