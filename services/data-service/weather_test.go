package main

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"net/url"
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

func TestOpenMeteoForecastFetchesAirQuality(t *testing.T) {
	newServer := func(airQualityStatus int) *httptest.Server {
		return httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
			writer.Header().Set("Content-Type", "application/json")
			if request.URL.Path == "/air-quality" {
				if request.URL.Query().Get("current") != "us_aqi" {
					t.Errorf("air quality current = %q", request.URL.Query().Get("current"))
				}
				if request.URL.Query().Get("latitude") != "28.228200" ||
					request.URL.Query().Get("longitude") != "112.938800" {
					t.Errorf("unexpected coordinates: %q / %q",
						request.URL.Query().Get("latitude"), request.URL.Query().Get("longitude"))
				}
				if airQualityStatus != http.StatusOK {
					writer.WriteHeader(airQualityStatus)
					return
				}
				_, _ = writer.Write([]byte(`{"current":{"time":"2026-08-30T12:00","us_aqi":40}}`))
				return
			}
			if request.URL.Path != "/forecast" {
				http.NotFound(writer, request)
				return
			}
			_, _ = writer.Write([]byte(`{
	            "timezone":"Asia/Shanghai",
	            "current":{"time":"2026-08-30T12:00","temperature_2m":31.4,
	              "relative_humidity_2m":58,"apparent_temperature":34.1,
	              "is_day":1,"weather_code":2,"wind_speed_10m":12.5,
	              "wind_direction_10m":175},
	            "hourly":{"time":["2026-08-30T12:00"],"temperature_2m":[31.4],
	              "apparent_temperature":[34.1],"relative_humidity_2m":[58],
	              "precipitation_probability":[10],"weather_code":[2],
	              "is_day":[1],"wind_speed_10m":[12.5]},
	            "daily":{"time":["2026-08-30"],"weather_code":[2],
	              "temperature_2m_max":[34],"temperature_2m_min":[25],
	              "precipitation_probability_max":[20],
	              "sunrise":["2026-08-30T06:03"],"sunset":["2026-08-30T18:55"]}
	          }`))
		}))
	}

	server := newServer(http.StatusOK)
	defer server.Close()
	provider := newOpenMeteoProvider()
	provider.client = server.Client()
	provider.forecastURL = server.URL + "/forecast"
	provider.airQualityURL = server.URL + "/air-quality"
	forecast, err := provider.Forecast(context.Background(), defaultWeatherState().Location, weatherUnitsMetric)
	if err != nil {
		t.Fatal(err)
	}
	if forecast.AirQuality == nil || forecast.AirQuality.UsAqi == nil ||
		*forecast.AirQuality.UsAqi != 40 || forecast.AirQuality.Category != "Good" ||
		forecast.AirQuality.Time != "2026-08-30T12:00" {
		t.Fatalf("unexpected air quality: %#v", forecast.AirQuality)
	}
	// The fixture intentionally omits wind_gusts_10m (legacy payload shape):
	// the mapped current conditions must leave WindGust nil instead of 0.
	if forecast.Current == nil || forecast.Current.WindGust != nil {
		t.Fatalf("missing gust must map to nil, got %#v", forecast.Current)
	}

	failing := newServer(http.StatusInternalServerError)
	defer failing.Close()
	provider = newOpenMeteoProvider()
	provider.client = failing.Client()
	provider.forecastURL = failing.URL + "/forecast"
	provider.airQualityURL = failing.URL + "/air-quality"
	forecast, err = provider.Forecast(context.Background(), defaultWeatherState().Location, weatherUnitsMetric)
	if err != nil {
		t.Fatal(err)
	}
	if forecast.AirQuality != nil {
		t.Fatalf("failed air quality must stay nil, got %#v", forecast.AirQuality)
	}
	if forecast.Current == nil || forecast.Current.WeatherCode != 2 {
		t.Fatalf("forecast did not survive air quality failure: %#v", forecast.Current)
	}
}

func TestUSAqiCategoryBands(t *testing.T) {
	cases := []struct {
		aqi      float64
		category string
	}{
		{40, "Good"},
		{60, "Moderate"},
		{120, "Unhealthy for Sensitive Groups"},
		{180, "Unhealthy"},
		{250, "Very Unhealthy"},
		{350, "Hazardous"},
		{-5, "Good"},
	}
	for _, testCase := range cases {
		if got := usAqiCategory(testCase.aqi); got != testCase.category {
			t.Fatalf("usAqiCategory(%v) = %q, want %q", testCase.aqi, got, testCase.category)
		}
	}
}

func TestWeatherAirQualityRoundTripsThroughState(t *testing.T) {
	aqi := 40.0
	state := defaultWeatherState()
	state.AirQuality = &WeatherAirQuality{
		Time:     "2026-08-30T12:00",
		UsAqi:    &aqi,
		Category: "Good",
	}

	raw, err := json.Marshal(state)
	if err != nil {
		t.Fatal(err)
	}
	var loaded WeatherState
	if err := json.Unmarshal(raw, &loaded); err != nil {
		t.Fatal(err)
	}
	airQuality := loaded.AirQuality
	if airQuality == nil || airQuality.Time != "2026-08-30T12:00" ||
		airQuality.UsAqi == nil || *airQuality.UsAqi != 40.0 ||
		airQuality.Category != "Good" {
		t.Fatalf("air quality did not survive persistence: %#v", airQuality)
	}

	empty := defaultWeatherState()
	raw, err = json.Marshal(empty)
	if err != nil {
		t.Fatal(err)
	}
	loaded = WeatherState{}
	if err := json.Unmarshal(raw, &loaded); err != nil {
		t.Fatal(err)
	}
	if loaded.AirQuality != nil {
		t.Fatalf("nil air quality did not stay nil: %#v", loaded.AirQuality)
	}
}

func TestWeatherCurrentWindGustRoundTripsThroughState(t *testing.T) {
	gust := 18.3
	state := defaultWeatherState()
	state.Current = &WeatherCurrent{
		Time:     "2026-10-16T11:41",
		WindGust: &gust,
	}

	raw, err := json.Marshal(state)
	if err != nil {
		t.Fatal(err)
	}
	var loaded WeatherState
	if err := json.Unmarshal(raw, &loaded); err != nil {
		t.Fatal(err)
	}
	if loaded.Current == nil || loaded.Current.WindGust == nil ||
		*loaded.Current.WindGust != 18.3 {
		t.Fatalf("wind gust did not survive persistence: %#v", loaded.Current)
	}

	empty := defaultWeatherState()
	raw, err = json.Marshal(empty)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(raw), "windGust") {
		t.Fatalf("nil wind gust must be omitted, got %s", raw)
	}
	loaded = WeatherState{}
	if err := json.Unmarshal(raw, &loaded); err != nil {
		t.Fatal(err)
	}
	if loaded.Current != nil && loaded.Current.WindGust != nil {
		t.Fatalf("nil wind gust did not stay nil: %#v", loaded.Current)
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
              "wind_direction_10m":175, "wind_gusts_10m":18.3},
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
	if forecast.Current.WindGust == nil || *forecast.Current.WindGust != 18.3 {
		t.Fatalf("wind gust = %#v, want 18.3", forecast.Current.WindGust)
	}
	if len(forecast.Hourly) != 2 || forecast.Hourly[1].PrecipitationChance != 20 {
		t.Fatalf("unexpected hourly forecast: %#v", forecast.Hourly)
	}
	if len(forecast.Daily) != 1 || forecast.Daily[0].Sunrise != "2026-08-30T06:03" {
		t.Fatalf("unexpected daily forecast: %#v", forecast.Daily)
	}
}

func TestOpenMeteoSummariesBatchCoordinates(t *testing.T) {
	var query url.Values
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		query = request.URL.Query()
		writer.Header().Set("Content-Type", "application/json")
		_, _ = writer.Write([]byte(`[
          {"latitude":28.228200,"longitude":112.938800,"timezone":"Asia/Shanghai",
           "current":{"time":"2026-10-16T11:41","temperature_2m":18.7,
             "is_day":1,"weather_code":2},
           "daily":{"temperature_2m_max":[22.4],"temperature_2m_min":[13.1]}},
          {"latitude":31.222500,"longitude":121.458100,"timezone":"Asia/Shanghai",
           "current":{"time":"2026-10-16T11:41","temperature_2m":23.2,
             "is_day":1,"weather_code":61},
           "daily":{"temperature_2m_max":[26.0],"temperature_2m_min":[19.5]}}
        ]`))
	}))
	defer server.Close()

	provider := newOpenMeteoProvider()
	provider.client = server.Client()
	provider.forecastURL = server.URL
	locations := []WeatherLocation{
		{ID: "open-meteo:1815577", Name: "长沙", Latitude: 28.2282, Longitude: 112.9388},
		{ID: "open-meteo:1796236", Name: "上海", Latitude: 31.2225, Longitude: 121.4581},
	}
	summaries, err := provider.Summaries(context.Background(), locations, weatherUnitsImperial)
	if err != nil {
		t.Fatal(err)
	}
	if query.Get("temperature_unit") != "fahrenheit" {
		t.Errorf("temperature unit = %q", query.Get("temperature_unit"))
	}
	if query.Get("latitude") != "28.228200,31.222500" ||
		query.Get("longitude") != "112.938800,121.458100" {
		t.Errorf("unexpected coordinates: %q / %q", query.Get("latitude"), query.Get("longitude"))
	}
	if query.Get("current") != "temperature_2m,is_day,weather_code" ||
		query.Get("daily") != "temperature_2m_max,temperature_2m_min" ||
		query.Get("forecast_days") != "1" {
		t.Errorf("unexpected summary request: %v", query)
	}
	if len(summaries) != 2 {
		t.Fatalf("summaries = %#v", summaries)
	}
	first, ok := summaries["open-meteo:1815577"]
	if !ok || first.Temperature != 18.7 || first.WeatherCode != 2 || !first.IsDay ||
		first.TempHigh != 22.4 || first.TempLow != 13.1 {
		t.Fatalf("unexpected Changsha summary: %#v", first)
	}
	if first.Time != "2026-10-16T11:41" {
		t.Fatalf("summary time = %q", first.Time)
	}
	second, ok := summaries["open-meteo:1796236"]
	if !ok || second.Temperature != 23.2 || second.WeatherCode != 61 ||
		second.TempHigh != 26.0 || second.TempLow != 19.5 {
		t.Fatalf("unexpected Shanghai summary: %#v", second)
	}
}

func TestOpenMeteoSummariesAcceptsSingleObjectResponse(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		writer.Header().Set("Content-Type", "application/json")
		_, _ = writer.Write([]byte(`{"latitude":28.228200,"longitude":112.938800,
          "timezone":"Asia/Shanghai",
          "current":{"time":"2026-10-16T11:41","temperature_2m":18.7,
            "is_day":0,"weather_code":2},
          "daily":{"temperature_2m_max":[22.4],"temperature_2m_min":[13.1]}}`))
	}))
	defer server.Close()

	provider := newOpenMeteoProvider()
	provider.client = server.Client()
	provider.forecastURL = server.URL
	locations := []WeatherLocation{
		{ID: "open-meteo:1815577", Name: "长沙", Latitude: 28.2282, Longitude: 112.9388},
	}
	summaries, err := provider.Summaries(context.Background(), locations, weatherUnitsMetric)
	if err != nil {
		t.Fatal(err)
	}
	summary, ok := summaries["open-meteo:1815577"]
	if !ok || summary.Temperature != 18.7 || summary.IsDay || summary.TempHigh != 22.4 {
		t.Fatalf("unexpected summary: %#v", summary)
	}
}

func TestWeatherLocationSummaryRoundTripsThroughState(t *testing.T) {
	state := defaultWeatherState()
	state.Locations[0].Summary = &WeatherLocationSummary{
		Time:        "2026-10-16T11:41",
		Temperature: 18.7,
		WeatherCode: 2,
		IsDay:       true,
		TempHigh:    22.4,
		TempLow:     13.1,
	}

	raw, err := json.Marshal(state)
	if err != nil {
		t.Fatal(err)
	}
	var loaded WeatherState
	if err := json.Unmarshal(raw, &loaded); err != nil {
		t.Fatal(err)
	}
	summary := loaded.Locations[0].Summary
	if summary == nil || summary.Time != state.Locations[0].Summary.Time ||
		summary.Temperature != 18.7 || summary.WeatherCode != 2 || !summary.IsDay ||
		summary.TempHigh != 22.4 || summary.TempLow != 13.1 {
		t.Fatalf("summary did not survive persistence: %#v", summary)
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

func (failingWeatherProvider) Summaries(context.Context, []WeatherLocation, string) (map[string]WeatherLocationSummary, error) {
	return nil, nil
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
