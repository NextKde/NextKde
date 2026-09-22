package main

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestNormalizeWeatherStateMigratesLegacyEmptyState(t *testing.T) {
	var state WeatherState
	normalizeWeatherState(&state)

	if state.SchemaVersion != weatherSchemaVersion {
		t.Fatalf("schema version = %d", state.SchemaVersion)
	}
	if state.Units != weatherUnitsMetric {
		t.Fatalf("units = %q", state.Units)
	}
	if state.Location.Name != "长沙" || len(state.Locations) != 1 {
		t.Fatalf("unexpected default location: %#v", state)
	}
	if state.Status != weatherStatusIdle {
		t.Fatalf("status = %q", state.Status)
	}
}

func TestOpenMeteoForecastMapsVersionedContract(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		if request.URL.Path != "/forecast" {
			http.NotFound(writer, request)
			return
		}
		if request.URL.Query().Get("temperature_unit") != "celsius" {
			t.Errorf("temperature unit = %q", request.URL.Query().Get("temperature_unit"))
		}
		writer.Header().Set("Content-Type", "application/json")
		_, _ = writer.Write([]byte(`{
            "timezone":"Asia/Shanghai",
            "current":{"time":"2026-08-30T12:00","temperature_2m":31.4,
              "relative_humidity_2m":58,"apparent_temperature":34.1,
              "is_day":1,"weather_code":2,"wind_speed_10m":12.5,
              "wind_direction_10m":175},
            "hourly":{"time":["2026-08-30T12:00","2026-08-30T13:00"],
              "temperature_2m":[31.4,32.0],"apparent_temperature":[34.1,34.8],
              "relative_humidity_2m":[58,56],"precipitation_probability":[10,20],
              "weather_code":[2,3],"is_day":[1,1],"wind_speed_10m":[12.5,13.1]},
            "daily":{"time":["2026-08-30"],"weather_code":[2],
              "temperature_2m_max":[34],"temperature_2m_min":[25],
              "precipitation_probability_max":[20],
              "sunrise":["2026-08-30T06:03"],"sunset":["2026-08-30T18:55"]}
          }`))
	}))
	defer server.Close()

	provider := newOpenMeteoProvider()
	provider.client = server.Client()
	provider.forecastURL = server.URL + "/forecast"
	forecast, err := provider.Forecast(context.Background(), defaultWeatherState().Location, weatherUnitsMetric)
	if err != nil {
		t.Fatal(err)
	}
	if forecast.Current == nil || forecast.Current.WeatherCode != 2 || !forecast.Current.IsDay {
		t.Fatalf("unexpected current conditions: %#v", forecast.Current)
	}
	if len(forecast.Hourly) != 2 || forecast.Hourly[1].PrecipitationChance != 20 {
		t.Fatalf("unexpected hourly forecast: %#v", forecast.Hourly)
	}
	if len(forecast.Daily) != 1 || forecast.Daily[0].Sunrise != "2026-08-30T06:03" {
		t.Fatalf("unexpected daily forecast: %#v", forecast.Daily)
	}
}

func TestOpenMeteoSearchNormalizesLocations(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		if request.URL.Query().Get("name") != "Changsha" {
			t.Errorf("query = %q", request.URL.Query().Get("name"))
		}
		_, _ = writer.Write([]byte(`{"results":[{"id":1815577,"name":"Changsha",
          "latitude":28.19874,"longitude":112.97087,"timezone":"Asia/Shanghai",
          "country_code":"cn","country":"China","admin1":"Hunan"}]}`))
	}))
	defer server.Close()

	provider := newOpenMeteoProvider()
	provider.client = server.Client()
	provider.geocodingURL = server.URL
	locations, err := provider.Search(context.Background(), "Changsha", "en", 8)
	if err != nil {
		t.Fatal(err)
	}
	if len(locations) != 1 || locations[0].ID != "open-meteo:1815577" ||
		locations[0].CountryCode != "CN" {
		t.Fatalf("unexpected locations: %#v", locations)
	}
}

func TestWeatherSnapshotUsesVersionedDataProtocol(t *testing.T) {
	weather := defaultWeatherState()
	service := &Service{state: State{Weather: weather}}
	response := service.handleRequest(DataRequest{
		Version: 1, RequestID: "weather-1", Operation: "weather.snapshot",
	})
	if !response.OK || response.Version != 1 || response.RequestID != "weather-1" {
		t.Fatalf("unexpected response: %#v", response)
	}
	result, ok := response.Result.(map[string]interface{})
	returned, weatherOK := result["weather"].(WeatherState)
	if !ok || !weatherOK || returned.SchemaVersion != weather.SchemaVersion ||
		returned.Location.ID != weather.Location.ID {
		t.Fatalf("unexpected weather result: %#v", response.Result)
	}
}

type failingWeatherProvider struct{}

func (failingWeatherProvider) Forecast(context.Context, WeatherLocation, string) (WeatherForecast, error) {
	return WeatherForecast{}, errors.New("network unavailable")
}

func (failingWeatherProvider) Search(context.Context, string, string, int) ([]WeatherLocation, error) {
	return nil, errors.New("network unavailable")
}

func TestFailedWeatherRefreshPreservesCachedConditions(t *testing.T) {
	directory := t.TempDir()
	state := defaultWeatherState()
	state.Status = weatherStatusReady
	state.Current = &WeatherCurrent{Time: "cached", Temperature: 24}
	service := &Service{
		state:           State{Weather: state},
		statePath:       filepath.Join(directory, "state.json"),
		snapshotPath:    filepath.Join(directory, "snapshot.json"),
		weatherProvider: failingWeatherProvider{},
		last:            time.Now(),
	}

	if !service.startWeatherRefresh(true) {
		t.Fatal("refresh was not accepted")
	}
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		service.mu.Lock()
		status := service.state.Weather.Status
		message := service.state.Weather.Error
		current := service.state.Weather.Current
		service.mu.Unlock()
		if status != weatherStatusLoading {
			if status != weatherStatusReady || current == nil || current.Time != "cached" {
				t.Fatalf("cached conditions were not preserved: %#v", service.state.Weather)
			}
			if !strings.Contains(message, "network unavailable") {
				t.Fatalf("unexpected error message %q", message)
			}
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatal("weather refresh did not complete")
}

func TestWeatherBackoffGrowsExponentiallyAndCaps(t *testing.T) {
	want := []time.Duration{
		1 * time.Minute, 2 * time.Minute, 4 * time.Minute, 8 * time.Minute,
		16 * time.Minute, 30 * time.Minute, 30 * time.Minute,
	}
	for streak, expected := range want {
		if got := weatherBackoff(streak + 1); got != expected {
			t.Fatalf("weatherBackoff(%d) = %v, want %v", streak+1, got, expected)
		}
	}
	if got := weatherBackoff(0); got != time.Minute {
		t.Fatalf("weatherBackoff(0) = %v, want 1m", got)
	}
	if got := weatherBackoff(1000); got != weatherBackoffMax {
		t.Fatalf("weatherBackoff(1000) = %v, want capped %v", got, weatherBackoffMax)
	}
}

// A failed refresh while offline (Current == nil) must schedule the next
// attempt via exponential backoff instead of allowing every 10s tick to
// spawn another HTTP request.
func TestFailedWeatherRefreshBacksOffAndGatesNextTick(t *testing.T) {
	directory := t.TempDir()
	state := defaultWeatherState()
	service := &Service{
		state:           State{Weather: state},
		statePath:       filepath.Join(directory, "state.json"),
		snapshotPath:    filepath.Join(directory, "snapshot.json"),
		weatherProvider: failingWeatherProvider{},
		last:            time.Now(),
	}
	service.state.Activity.TodayApps = map[string]AppUsage{}
	service.state.Activity.UptimeByDay = map[string]float64{}

	if !service.startWeatherRefresh(true) {
		t.Fatal("refresh was not accepted")
	}
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		service.mu.Lock()
		status := service.state.Weather.Status
		service.mu.Unlock()
		if status == weatherStatusError {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	service.mu.Lock()
	weather := service.state.Weather
	streak := service.weatherFailStreak
	service.mu.Unlock()
	if weather.Status != weatherStatusError || weather.Current != nil {
		t.Fatalf("unexpected weather after failure: %#v", weather)
	}
	if streak != 1 {
		t.Fatalf("fail streak = %d, want 1", streak)
	}
	expectedEarliest := time.Now().Add(weatherBackoff(1) - 5*time.Second).UnixMilli()
	if weather.NextRefreshAt < expectedEarliest {
		t.Fatalf("NextRefreshAt = %d, want >= %d (backoff)", weather.NextRefreshAt, expectedEarliest)
	}
	// The non-forced tick must now be gated by NextRefreshAt even though
	// Current is nil.
	if service.startWeatherRefresh(false) {
		t.Fatal("backoff gate did not suppress the automatic refresh")
	}
}
