package main

// MetricSample keeps one fixed-interval telemetry point. Ratios are 0..1 and
// temperatures are in millidegrees Celsius, so every consumer formats the same
// canonical units without touching /proc itself.
type MetricSample struct {
	At            int64   `json:"at"`
	CPU           float64 `json:"cpu,omitempty"`
	Memory        float64 `json:"memory,omitempty"`
	Disk          float64 `json:"disk,omitempty"`
	Frequency     float64 `json:"frequencyMhz,omitempty"`
	CurrentMilliC float64 `json:"currentMilliC,omitempty"`
	AverageMilliC float64 `json:"averageMilliC,omitempty"`
	MaximumMilliC float64 `json:"maximumMilliC,omitempty"`
}

type Metrics struct {
	CPU                  float64         `json:"cpu"`
	Memory               float64         `json:"memory"`
	Disk                 float64         `json:"disk"`
	FrequencyMHz         float64         `json:"frequencyMhz"`
	CurrentMilliC        float64         `json:"currentMilliC"`
	Maximum5MinuteMilliC float64         `json:"maximum5MinuteMilliC"`
	AverageMilliC        float64         `json:"averageMilliC"`
	MaximumMilliC        float64         `json:"maximumMilliC"`
	MemoryUsedBytes      float64         `json:"memoryUsedBytes"`
	MemoryTotalBytes     float64         `json:"memoryTotalBytes"`
	DiskUsedBytes        float64         `json:"diskUsedBytes"`
	DiskTotalBytes       float64         `json:"diskTotalBytes"`
	Sensors              []SensorReading `json:"sensors"`
	History              []MetricSample  `json:"history"`
}

// SensorReading is one live hwmon/thermal reading, enumerated exactly like the
// old shell sampler so the sensor dashboard keeps its device/label detail.
type SensorReading struct {
	Source string  `json:"source"`
	Device string  `json:"device"`
	Label  string  `json:"label"`
	MilliC float64 `json:"milliC"`
}

type AppUsage struct {
	Name    string  `json:"name,omitempty"`
	Icon    string  `json:"icon,omitempty"`
	Seconds float64 `json:"seconds"`
}

type Activity struct {
	Active    bool                `json:"active"`
	ActiveApp string              `json:"activeApp,omitempty"`
	TodayApps map[string]AppUsage `json:"todayApps"`
	// TodayAppsDay records which calendar day TodayApps was accumulated for;
	// without it a restarted service cannot tell stale rows from today's.
	TodayAppsDay string             `json:"todayAppsDay,omitempty"`
	UptimeByDay  map[string]float64 `json:"uptimeByDay"`
	// JournalSeeded marks that journald boot history was already folded into
	// UptimeByDay, so seeding never runs twice.
	JournalSeeded bool `json:"journalSeeded"`
}

type DesktopEntry struct {
	Name       string `json:"name"`
	Title      string `json:"title,omitempty"`
	Path       string `json:"path"`
	Kind       string `json:"kind"`
	Icon       string `json:"icon,omitempty"`
	ModifiedAt int64  `json:"modifiedAt"`
	Output     string `json:"output,omitempty"`
	fileID     string
}

type Desktop struct {
	Directory string         `json:"directory"`
	Entries   []DesktopEntry `json:"entries"`
	UpdatedAt int64          `json:"updatedAt"`
}

type Snapshot struct {
	SchemaVersion int          `json:"schemaVersion"`
	GeneratedAt   int64        `json:"generatedAt"`
	Metrics       Metrics      `json:"metrics"`
	Activity      Activity     `json:"activity"`
	Desktop       Desktop      `json:"desktop"`
	Weather       WeatherState `json:"weather"`
}

type State struct {
	Metrics           Metrics                     `json:"metrics"`
	Activity          Activity                    `json:"activity"`
	Desktop           Desktop                     `json:"desktop"`
	Weather           WeatherState                `json:"weather"`
	DesktopPlacements map[string]DesktopPlacement `json:"desktopPlacements,omitempty"`
}
