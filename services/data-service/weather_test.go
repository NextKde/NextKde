package main

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"testing/synctest"
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
	// The fixture also omits uv_index, visibility and pressure_msl (legacy
	// payload shape): all optional fields must stay nil for backward compat.
	if forecast.Current == nil || forecast.Current.UvIndex != nil ||
		forecast.Current.Visibility != nil || forecast.Current.Pressure != nil {
		t.Fatalf("missing uv/visibility/pressure must map to nil, got %#v", forecast.Current)
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

func TestWeatherCurrentUvIndexAndVisibilityRoundTripsThroughState(t *testing.T) {
	uvIndex := 6.4
	visibility := 24140.0
	state := defaultWeatherState()
	state.Current = &WeatherCurrent{
		Time:       "2026-10-16T11:41",
		UvIndex:    &uvIndex,
		Visibility: &visibility,
	}

	raw, err := json.Marshal(state)
	if err != nil {
		t.Fatal(err)
	}
	var loaded WeatherState
	if err := json.Unmarshal(raw, &loaded); err != nil {
		t.Fatal(err)
	}
	if loaded.Current == nil || loaded.Current.UvIndex == nil ||
		*loaded.Current.UvIndex != 6.4 || loaded.Current.Visibility == nil ||
		*loaded.Current.Visibility != 24140.0 {
		t.Fatalf("uv index and visibility did not survive persistence: %#v", loaded.Current)
	}

	empty := defaultWeatherState()
	raw, err = json.Marshal(empty)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(raw), "uvIndex") || strings.Contains(string(raw), "visibility") {
		t.Fatalf("nil uv index and visibility must be omitted, got %s", raw)
	}
	loaded = WeatherState{}
	if err := json.Unmarshal(raw, &loaded); err != nil {
		t.Fatal(err)
	}
	if loaded.Current != nil && (loaded.Current.UvIndex != nil || loaded.Current.Visibility != nil) {
		t.Fatalf("nil uv index and visibility did not stay nil: %#v", loaded.Current)
	}
}

func TestWeatherCurrentPressureRoundTripsThroughState(t *testing.T) {
	pressure := 1014.2
	state := defaultWeatherState()
	state.Current = &WeatherCurrent{
		Time:     "2026-10-16T11:41",
		Pressure: &pressure,
	}

	raw, err := json.Marshal(state)
	if err != nil {
		t.Fatal(err)
	}
	var loaded WeatherState
	if err := json.Unmarshal(raw, &loaded); err != nil {
		t.Fatal(err)
	}
	if loaded.Current == nil || loaded.Current.Pressure == nil ||
		*loaded.Current.Pressure != 1014.2 {
		t.Fatalf("pressure did not survive persistence: %#v", loaded.Current)
	}

	empty := defaultWeatherState()
	raw, err = json.Marshal(empty)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(raw), "pressure") {
		t.Fatalf("nil pressure must be omitted, got %s", raw)
	}
	loaded = WeatherState{}
	if err := json.Unmarshal(raw, &loaded); err != nil {
		t.Fatal(err)
	}
	if loaded.Current != nil && loaded.Current.Pressure != nil {
		t.Fatalf("nil pressure did not stay nil: %#v", loaded.Current)
	}
}

func TestWeatherCurrentMoonPhaseRoundTripsThroughState(t *testing.T) {
	phase := 0.342
	illumination := 78.5
	state := defaultWeatherState()
	state.Current = &WeatherCurrent{
		Time:             "2026-10-16T11:41",
		MoonPhase:        &phase,
		MoonIllumination: &illumination,
	}

	raw, err := json.Marshal(state)
	if err != nil {
		t.Fatal(err)
	}
	var loaded WeatherState
	if err := json.Unmarshal(raw, &loaded); err != nil {
		t.Fatal(err)
	}
	if loaded.Current == nil || loaded.Current.MoonPhase == nil ||
		*loaded.Current.MoonPhase != 0.342 || loaded.Current.MoonIllumination == nil ||
		*loaded.Current.MoonIllumination != 78.5 {
		t.Fatalf("moon phase did not survive persistence: %#v", loaded.Current)
	}

	empty := defaultWeatherState()
	raw, err = json.Marshal(empty)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(raw), "moonPhase") || strings.Contains(string(raw), "moonIllumination") {
		t.Fatalf("nil moon phase must be omitted, got %s", raw)
	}
	loaded = WeatherState{}
	if err := json.Unmarshal(raw, &loaded); err != nil {
		t.Fatal(err)
	}
	if loaded.Current != nil && (loaded.Current.MoonPhase != nil || loaded.Current.MoonIllumination != nil) {
		t.Fatalf("nil moon phase did not stay nil: %#v", loaded.Current)
	}
}

// TestMoonPhaseAtKnownDates checks the mean-synodic-month approximation
// against known lunations. The approximation drifts by roughly +/-0.5 day
// over decades, so assertions on real dates use generous intervals.
func TestMoonPhaseAtKnownDates(t *testing.T) {
	cases := []struct {
		name         string
		when         time.Time
		phaseMinimum float64
		phaseMaximum float64
		illumMin     float64
		illumMax     float64
	}{
		{
			// moonEpoch itself is a known new moon: phase must be ~0.
			name:         "epoch is new moon",
			when:         moonEpoch,
			phaseMinimum: 0,
			phaseMaximum: 0.02,
			illumMin:     0,
			illumMax:     0.1,
		},
		{
			// One mean synodic month after the epoch is again a new moon
			// (within the approximation's tolerance).
			name:         "one synodic month later is new moon",
			when:         moonEpoch.Add(time.Duration(29.530588853 * 24 * float64(time.Hour))),
			phaseMinimum: 0,
			phaseMaximum: 0.05,
			illumMin:     0,
			illumMax:     2.5,
		},
		{
			// 2000-01-21 20:02 UTC is near first quarter (phase ~0.5), so the
			// illuminated fraction (1-cos(2*pi*phase))/2*100 is near 100:
			// phase 0.44..0.56 maps to illumination ~92.6..99.7, hence the
			// 92-100 window below.
			name:         "first quarter near 2000-01-21",
			when:         time.Date(2000, time.January, 21, 20, 2, 0, 0, time.UTC),
			phaseMinimum: 0.44,
			phaseMaximum: 0.56,
			illumMin:     92,
			illumMax:     100,
		},
	}
	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			phase, illumination := moonPhaseAt(testCase.when)
			if phase < testCase.phaseMinimum || phase >= testCase.phaseMaximum {
				t.Fatalf("phase = %v, want [%v, %v)", phase, testCase.phaseMinimum, testCase.phaseMaximum)
			}
			if illumination < testCase.illumMin || illumination > testCase.illumMax {
				t.Fatalf("illumination = %v, want [%v, %v]", illumination, testCase.illumMin, testCase.illumMax)
			}
		})
	}

	// Any instant must map into the documented ranges.
	for _, when := range []time.Time{
		moonEpoch.Add(-1000 * 24 * time.Hour),
		time.Date(1900, time.June, 15, 3, 30, 0, 0, time.UTC),
		time.Date(2100, time.March, 1, 12, 0, 0, 0, time.UTC),
		time.Now().UTC(),
	} {
		phase, illumination := moonPhaseAt(when)
		if phase < 0 || phase >= 1 {
			t.Fatalf("phase %v out of [0,1) at %v", phase, when)
		}
		if illumination < 0 || illumination > 100 {
			t.Fatalf("illumination %v out of [0,100] at %v", illumination, when)
		}
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
              "wind_direction_10m":175, "wind_gusts_10m":18.3,
              "uv_index":6.4, "visibility":24140, "pressure_msl":1014.2},
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
	if forecast.Current.UvIndex == nil || *forecast.Current.UvIndex != 6.4 {
		t.Fatalf("uv index = %#v, want 6.4", forecast.Current.UvIndex)
	}
	if forecast.Current.Visibility == nil || *forecast.Current.Visibility != 24140 {
		t.Fatalf("visibility = %#v, want 24140", forecast.Current.Visibility)
	}
	if forecast.Current.Pressure == nil || *forecast.Current.Pressure != 1014.2 {
		t.Fatalf("pressure = %#v, want 1014.2", forecast.Current.Pressure)
	}
	// Moon data is computed locally at mapping time, independent of the fixture.
	if forecast.Current.MoonPhase == nil || *forecast.Current.MoonPhase < 0 || *forecast.Current.MoonPhase >= 1 {
		t.Fatalf("moon phase = %#v, want a value in [0,1)", forecast.Current.MoonPhase)
	}
	if forecast.Current.MoonIllumination == nil || *forecast.Current.MoonIllumination < 0 || *forecast.Current.MoonIllumination > 100 {
		t.Fatalf("moon illumination = %#v, want a value in [0,100]", forecast.Current.MoonIllumination)
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
	synctest.Test(t, func(t *testing.T) {
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
		synctest.Wait()
		weather := service.state.Weather
		if weather.Status != weatherStatusReady || weather.Current == nil || weather.Current.Time != "cached" {
			t.Fatalf("cached conditions were not preserved: %#v", weather)
		}
		if !strings.Contains(weather.Error, "network unavailable") {
			t.Fatalf("unexpected error message %q", weather.Error)
		}
	})
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
	synctest.Test(t, func(t *testing.T) {
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
		synctest.Wait()
		weather := service.state.Weather
		streak := service.weatherFailStreak
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
	})
}

// Switching back to a city the user already visited must paint from cache
// instead of wiping the snapshot and waiting on the network again.
func TestWeatherLocationSwitchServesCachedSnapshot(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		directory := t.TempDir()
		state := defaultWeatherState()
		state.Location = WeatherLocation{ID: "city-a", Name: "A"}
		service := &Service{
			state:           State{Weather: state},
			statePath:       filepath.Join(directory, "state.json"),
			snapshotPath:    filepath.Join(directory, "snapshot.json"),
			weatherProvider: fixedWeatherProvider{temperature: 21},
			last:            time.Now(),
		}

		if !service.startWeatherRefresh(true) {
			t.Fatal("initial refresh was not accepted")
		}
		synctest.Wait()
		if service.state.Weather.Current == nil {
			t.Fatal("initial fetch did not populate current conditions")
		}

		// Visit a second city: nothing is cached yet, so the snapshot is wiped
		// and marked loading, but the fetch must be accepted even though a
		// previous request just finished.
		if err := service.setWeatherLocation(WeatherLocation{ID: "city-b", Name: "B"}); err != nil {
			t.Fatalf("setWeatherLocation(B): %v", err)
		}
		synctest.Wait()

		// Back to the first city: content must be present immediately, without
		// waiting for synctest.Wait() / the network.
		if err := service.setWeatherLocation(WeatherLocation{ID: "city-a", Name: "A"}); err != nil {
			t.Fatalf("setWeatherLocation(A): %v", err)
		}
		weather := service.state.Weather
		if weather.Current == nil {
			t.Fatal("cached city snapshot was not restored on switch")
		}
		// The background refresh may already have flipped the status to loading;
		// what matters is that content is present without waiting for the network.
		if weather.Status != weatherStatusReady && weather.Status != weatherStatusLoading {
			t.Fatalf("status = %q, want ready or loading", weather.Status)
		}
		synctest.Wait()
		if got := service.state.Weather.Status; got != weatherStatusReady {
			t.Fatalf("status after refresh = %q, want %q", got, weatherStatusReady)
		}
	})
}

type fixedWeatherProvider struct{ temperature float64 }

func (p fixedWeatherProvider) Forecast(context.Context, WeatherLocation, string) (WeatherForecast, error) {
	return WeatherForecast{
		Current: &WeatherCurrent{Time: "now", Temperature: p.temperature},
		Hourly:  []WeatherHourlyPoint{{Time: "now", Temperature: p.temperature}},
		Daily:   []WeatherDay{{Date: "today", TemperatureMaximum: p.temperature + 3, TemperatureMinimum: p.temperature - 3}},
	}, nil
}

func (fixedWeatherProvider) Search(context.Context, string, string, int) ([]WeatherLocation, error) {
	return nil, nil
}

func (fixedWeatherProvider) Summaries(context.Context, []WeatherLocation, string) (map[string]WeatherLocationSummary, error) {
	return map[string]WeatherLocationSummary{}, nil
}

func TestRemoveWeatherLocationPersistsEmptyAndRejectsLateForecast(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		directory := t.TempDir()
		state := defaultWeatherState()
		a := state.Location
		b := WeatherLocation{ID: "city-b", Name: "B", Latitude: 30, Longitude: 120}
		c := WeatherLocation{ID: "city-c", Name: "C", Latitude: 31, Longitude: 121}
		state.Locations = []WeatherLocation{a, b, c}
		state.Current = &WeatherCurrent{Temperature: 24}
		service := &Service{state: State{Weather: state}, last: time.Now(),
			statePath: filepath.Join(directory, "state.json"), snapshotPath: filepath.Join(directory, "snapshot.json"),
			weatherProvider: fixedWeatherProvider{temperature: 30}}
		original := service.state.Weather.Current
		// Deleting a background city must preserve the current forecast.
		response := service.handleRequest(DataRequest{Version: 1, RequestID: "delete-b",
			Operation: "weather.remove-location", Payload: map[string]interface{}{"id": b.ID}})
		if !response.OK || len(service.state.Weather.Locations) != 2 || service.state.Weather.Current != original {
			t.Fatalf("background removal changed forecast: %#v", service.state.Weather)
		}
		if err := service.removeWeatherLocation(a.ID); err != nil {
			t.Fatal(err)
		}
		synctest.Wait()
		if service.state.Weather.Location.ID != c.ID || len(service.state.Weather.Locations) != 1 {
			t.Fatalf("selected deletion did not select remaining city: %#v", service.state.Weather)
		}
		oldSerial := service.weatherRequestSerial
		if err := service.removeWeatherLocation(c.ID); err != nil {
			t.Fatal(err)
		}
		service.fetchWeather(oldSerial, fixedWeatherProvider{temperature: 99}, c, weatherUnitsMetric)
		if service.state.Weather.Current != nil || service.state.Weather.Location.ID != "" || service.startWeatherRefresh(true) {
			t.Fatal("deleted city's late forecast or refresh resurrected empty state")
		}
		raw, err := os.ReadFile(service.statePath)
		if err != nil {
			t.Fatal(err)
		}
		var restored State
		if err := json.Unmarshal(raw, &restored); err != nil {
			t.Fatal(err)
		}
		normalizeWeatherState(&restored.Weather)
		if restored.Weather.Locations == nil || len(restored.Weather.Locations) != 0 || restored.Weather.Location.ID != "" {
			t.Fatalf("empty selection did not survive restart: %#v", restored.Weather)
		}
		if err := service.removeWeatherLocation(c.ID); err != nil {
			t.Fatal("repeat removal must be idempotent")
		}
		if err := service.setWeatherLocation(b); err != nil {
			t.Fatal(err)
		}
		synctest.Wait()
		if service.state.Weather.Location.ID != b.ID || len(service.state.Weather.Locations) != 1 {
			t.Fatal("cannot add a city after deleting the last one")
		}
	})
}
