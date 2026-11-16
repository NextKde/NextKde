package main

import (
	"golang.org/x/sys/unix"
	"math"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

const temperaturePeakWindow = 5 * time.Minute

// parseF64 reads a /proc or /sys file that holds a single non-negative number.
func parseF64(path string) float64 {
	raw, err := os.ReadFile(path)
	if err != nil {
		return 0
	}
	value, err := strconv.ParseFloat(strings.TrimSpace(string(raw)), 64)
	if err != nil || value < 0 {
		return 0
	}
	return value
}

// readCPU returns the machine-wide CPU busy ratio between this call and the
// previous one. The first call after a restart reports 0 because there is no
// prior /proc/stat delta to compare against.
func (s *Service) readCPU() float64 {
	raw, err := os.ReadFile("/proc/stat")
	if err != nil {
		return 0
	}
	fields := strings.Fields(strings.SplitN(string(raw), "\n", 2)[0])
	if len(fields) < 5 {
		return 0
	}
	total, idle := float64(0), float64(0)
	for i := 1; i < len(fields); i++ {
		n, _ := strconv.ParseFloat(fields[i], 64)
		total += n
		if i == 4 || i == 5 {
			idle += n
		}
	}
	if s.prevCPUTotal > 0 && total > s.prevCPUTotal {
		usage := 1 - (idle-s.prevCPUIdle)/(total-s.prevCPUTotal)
		s.prevCPUTotal = total
		s.prevCPUIdle = idle
		return math.Max(0, math.Min(1, usage))
	}
	s.prevCPUTotal = total
	s.prevCPUIdle = idle
	return 0
}

func readMem() (used, total float64) {
	raw, err := os.ReadFile("/proc/meminfo")
	if err != nil {
		return 0, 0
	}
	memTotal, memAvailable := float64(0), float64(0)
	for _, l := range strings.Split(string(raw), "\n") {
		f := strings.Fields(l)
		if len(f) < 2 {
			continue
		}
		v, _ := strconv.ParseFloat(f[1], 64)
		switch f[0] {
		case "MemTotal:":
			memTotal = v
		case "MemAvailable:":
			memAvailable = v
		}
	}
	if memTotal <= 0 {
		return 0, 0
	}
	// /proc/meminfo counts in kibibytes.
	used = math.Max(0, memTotal-memAvailable)
	return used * 1024, memTotal * 1024
}

// readDisk reports used/total bytes of the root filesystem via statfs — the
// same counters df -B1 prints — without forking a process per sample.
func readDisk() (used, total float64) {
	var stat unix.Statfs_t
	if err := unix.Statfs("/", &stat); err != nil || stat.Bsize <= 0 || stat.Blocks == 0 {
		return 0, 0
	}
	bsize := uint64(stat.Bsize)
	total = float64(stat.Blocks * bsize)
	used = float64((stat.Blocks - stat.Bfree) * bsize)
	return used, total
}

func readFrequency() float64 {
	// Prefer the live cpufreq policies; the /proc/cpuinfo fallback covers
	// machines without an intel_pstate/CPUFreq driver reporting a current rate.
	entries, _ := filepath.Glob("/sys/devices/system/cpu/cpufreq/policy*/scaling_cur_freq")
	sum, count := float64(0), float64(0)
	for _, p := range entries {
		if value := parseF64(p); value > 0 {
			sum += value
			count++
		}
	}
	if count > 0 {
		return sum / count / 1000 // kHz -> MHz
	}
	raw, err := os.ReadFile("/proc/cpuinfo")
	if err != nil {
		return 0
	}
	sum, count = 0, 0
	for _, line := range strings.Split(string(raw), "\n") {
		fields := strings.Fields(line)
		if len(fields) >= 4 && fields[0] == "cpu" && fields[1] == "MHz" {
			if value, err := strconv.ParseFloat(fields[3], 64); err == nil {
				sum += value
				count++
			}
		}
	}
	if count == 0 {
		return 0
	}
	return sum / count
}

// cpuTemperaturePriority selects one canonical package-level reading instead
// of averaging duplicate ACPI, thermal-zone, and per-core views of the same
// processor. Direct hwmon package sensors are preferred, then package thermal
// zones, with CPU-labelled zones and individual cores as fallbacks.
func cpuTemperaturePriority(reading SensorReading) int {
	if reading.MilliC <= 0 {
		return 0
	}
	source := strings.ToLower(reading.Source)
	device := strings.ToLower(reading.Device)
	label := strings.ToLower(reading.Label)

	switch {
	case device == "coretemp" && strings.Contains(label, "package id"):
		return 100
	case (device == "k10temp" || strings.Contains(device, "zenpower")) && label == "tctl":
		return 100
	case (device == "k10temp" || strings.Contains(device, "zenpower")) && label == "tdie":
		return 95
	case source == "thermal" && label == "x86_pkg_temp":
		return 90
	case strings.Contains(label, "package") || strings.Contains(label, "pkg"):
		return 80
	case source == "thermal" && strings.Contains(label, "tcpu"):
		return 70
	case device == "coretemp" && strings.HasPrefix(label, "core "):
		return 60
	case source == "thermal" && strings.Contains(label, "cpu"):
		return 50
	default:
		return 0
	}
}

func selectCurrentCPUTemperature(readings []SensorReading) float64 {
	priority := 0
	current := float64(-1)
	for _, reading := range readings {
		candidatePriority := cpuTemperaturePriority(reading)
		if candidatePriority == 0 || candidatePriority < priority {
			continue
		}
		if candidatePriority > priority || reading.MilliC > current {
			priority = candidatePriority
			current = reading.MilliC
		}
	}
	return current
}

// sensorProbe is one enumerated temperature input. Probes are collected once
// per service lifetime (see Service.sensorsOnce): sysfs hwmon/thermal device
// topology and labels do not meaningfully change at runtime, so re-globbing
// and re-reading label/name files on every 10s sample would be pure waste.
// Only inputPath — the live value — is read per sample.
type sensorProbe struct {
	source    string
	device    string
	label     string
	inputPath string
}

// enumerateSensors performs the one-time thermal-zone/hwmon walk.
func enumerateSensors() []sensorProbe {
	var probes []sensorProbe
	zones, _ := filepath.Glob("/sys/class/thermal/thermal_zone*/type")
	for _, t := range zones {
		label := strings.TrimSpace(string(readRaw(t)))
		index := strings.TrimPrefix(t, "/sys/class/thermal/thermal_zone")
		index = strings.TrimSuffix(index, "/type")
		if !strings.Contains(strings.ToLower(label), "cpu") &&
			!strings.Contains(strings.ToLower(label), "pkg") {
			continue
		}
		probes = append(probes, sensorProbe{
			source: "thermal", device: "kernel", label: label,
			inputPath: "/sys/class/thermal/thermal_zone" + index + "/temp",
		})
	}
	hwmons, _ := filepath.Glob("/sys/class/hwmon/hwmon*")
	for _, hwmon := range hwmons {
		device := strings.TrimSpace(string(readRaw(hwmon + "/name")))
		inputs, _ := filepath.Glob(hwmon + "/temp*_input")
		for _, input := range inputs {
			index := strings.TrimPrefix(input, hwmon+"/temp")
			index = strings.TrimSuffix(index, "_input")
			label := strings.TrimSpace(string(readRaw(hwmon + "/temp" + index + "_label")))
			if label == "" {
				label = "Temperature " + index
			}
			probes = append(probes, sensorProbe{
				source: "hwmon", device: device, label: label, inputPath: input,
			})
		}
	}
	return probes
}

func (s *Service) readTemperature() (current float64, readings []SensorReading) {
	s.sensorsOnce.Do(func() { s.sensors = enumerateSensors() })
	for _, probe := range s.sensors {
		readings = append(readings, SensorReading{
			Source: probe.source, Device: probe.device,
			Label: probe.label, MilliC: parseF64(probe.inputPath),
		})
	}
	return selectCurrentCPUTemperature(readings), readings
}

func metricSampleTemperature(sample MetricSample) float64 {
	if sample.CurrentMilliC > 0 {
		return sample.CurrentMilliC
	}
	// State written before currentMilliC existed stored an instantaneous
	// thermal-zone maximum and average. Prefer the former during the five-minute
	// migration window so an actual recent peak is not understated.
	if sample.MaximumMilliC > 0 {
		return sample.MaximumMilliC
	}
	if sample.AverageMilliC > 0 {
		return sample.AverageMilliC
	}
	return -1
}

func rollingTemperatureMaximum(history []MetricSample, nowMillis int64, window time.Duration) float64 {
	cutoff := nowMillis - window.Milliseconds()
	maximum := float64(-1)
	for _, sample := range history {
		if sample.At < cutoff || sample.At > nowMillis {
			continue
		}
		if value := metricSampleTemperature(sample); value > maximum {
			maximum = value
		}
	}
	return maximum
}

// readRaw returns a file's bytes trimmed of whitespace; missing/unreadable
// files yield an empty slice so callers never fail on virtual filesystems.
func readRaw(path string) []byte {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil
	}
	return []byte(strings.TrimSpace(string(raw)))
}

// sample performs every sysfs/proc read before taking s.mu: the probes take
// 5-15ms and would otherwise stall settle/snapshot/persist writers on every
// 10s tick. s.mu is held only for the state mutation and History append.
// Callers are serialized on the main goroutine (startup + tick select), so
// the prevCPU counters in readCPU and the sensorsOnce cache stay race-free.
func (s *Service) sample() {
	now := time.Now()
	current, readings := s.readTemperature()
	memUsed, memTotal := readMem()
	diskUsed, diskTotal := readDisk()
	cpu := s.readCPU()
	frequency := readFrequency()

	s.mu.Lock()
	defer s.mu.Unlock()
	s.state.Metrics.CPU = cpu
	// Ratios must stay finite: a failed probe yields NaN, which json.Marshal
	// rejects and would silently kill the whole snapshot write.
	if memTotal > 0 {
		s.state.Metrics.Memory = memUsed / memTotal
	}
	if diskTotal > 0 {
		s.state.Metrics.Disk = diskUsed / diskTotal
	}
	s.state.Metrics.FrequencyMHz = frequency
	s.state.Metrics.CurrentMilliC = current
	s.state.Metrics.MemoryUsedBytes = memUsed
	s.state.Metrics.MemoryTotalBytes = memTotal
	s.state.Metrics.DiskUsedBytes = diskUsed
	s.state.Metrics.DiskTotalBytes = diskTotal
	s.state.Metrics.Sensors = readings
	sample := MetricSample{At: now.UnixMilli(), CPU: cpu, Memory: s.state.Metrics.Memory,
		Disk: s.state.Metrics.Disk, Frequency: frequency, CurrentMilliC: current,
		// Keep writing the old fields for one compatibility cycle. New readers
		// consume currentMilliC and maximum5MinuteMilliC.
		AverageMilliC: current, MaximumMilliC: current}
	s.state.Metrics.History = append(s.state.Metrics.History, sample)
	if len(s.state.Metrics.History) > 360 {
		s.state.Metrics.History = s.state.Metrics.History[len(s.state.Metrics.History)-360:]
	}
	maximum5Minute := rollingTemperatureMaximum(
		s.state.Metrics.History, now.UnixMilli(), temperaturePeakWindow)
	s.state.Metrics.Maximum5MinuteMilliC = maximum5Minute
	// Compatibility aliases keep older shell surfaces correct while every
	// in-tree consumer migrates to the explicit field names.
	s.state.Metrics.AverageMilliC = current
	s.state.Metrics.MaximumMilliC = maximum5Minute
}
