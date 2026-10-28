package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"net/http"
	"net/url"
	"strings"
	"time"
	"unicode/utf8"
)

const (
	weatherSchemaVersion   = 1
	weatherProviderName    = "open-meteo"
	weatherUnitsMetric     = "metric"
	weatherUnitsImperial   = "imperial"
	weatherStatusIdle      = "idle"
	weatherStatusLoading   = "loading"
	weatherStatusReady     = "ready"
	weatherStatusError     = "error"
	weatherRefreshInterval = time.Hour
	weatherStaleInterval   = 2 * time.Hour
	weatherRequestTimeout  = 20 * time.Second
	weatherMaximumBodySize = 2 << 20
	// Failure backoff doubles per consecutive fetch failure starting at one
	// minute and caps at half an hour, so an offline machine retries every
	// 30min instead of spawning an HTTP request on every 10s tick.
	weatherBackoffBase = time.Minute
	weatherBackoffMax  = 30 * time.Minute
	// maxCachedWeather bounds the per-location snapshot cache held in memory.
	maxCachedWeather = 20
)

type WeatherLocation struct {
	ID          string                  `json:"id"`
	Name        string                  `json:"name"`
	Admin1      string                  `json:"admin1,omitempty"`
	Country     string                  `json:"country,omitempty"`
	CountryCode string                  `json:"countryCode,omitempty"`
	Latitude    float64                 `json:"latitude"`
	Longitude   float64                 `json:"longitude"`
	Timezone    string                  `json:"timezone,omitempty"`
	Summary     *WeatherLocationSummary `json:"summary,omitempty"`
}

// WeatherLocationSummary is the compact per-city snapshot shown by sidebar
// cards: current conditions plus today's range, in the state's units.
type WeatherLocationSummary struct {
	Time        string  `json:"time"`
	Temperature float64 `json:"temperature"`
	WeatherCode int     `json:"weatherCode"`
	IsDay       bool    `json:"isDay"`
	TempHigh    float64 `json:"tempHigh"`
	TempLow     float64 `json:"tempLow"`
}

// WeatherAirQuality carries the current US AQI reading for the selected
// location. UsAqi is nil when the provider returned no reading.
type WeatherAirQuality struct {
	Time     string   `json:"time"`
	UsAqi    *float64 `json:"usAqi"`
	Category string   `json:"category,omitempty"`
}

type WeatherCurrent struct {
	Time             string  `json:"time"`
	Temperature      float64 `json:"temperature"`
	ApparentTemp     float64 `json:"apparentTemperature"`
	RelativeHumidity float64 `json:"relativeHumidity"`
	IsDay            bool    `json:"isDay"`
	WeatherCode      int     `json:"weatherCode"`
	WindSpeed        float64 `json:"windSpeed"`
	WindDirection    float64 `json:"windDirection"`
	// WindGust is the recent maximum gust in the state's wind unit. It is nil
	// when the persisted snapshot predates the field or the provider omitted it.
	WindGust *float64 `json:"windGust,omitempty"`
	// UvIndex is the dimensionless current UV index. It is nil when the
	// persisted snapshot predates the field or the provider omitted it.
	UvIndex *float64 `json:"uvIndex,omitempty"`
	// Visibility is the current visibility in meters; consumers convert to
	// their own display unit. It is nil when the persisted snapshot predates
	// the field or the provider omitted it.
	Visibility *float64 `json:"visibility,omitempty"`
	// Pressure is the current sea-level pressure in hPa. It is nil when the
	// persisted snapshot predates the field or the provider omitted it.
	Pressure *float64 `json:"pressure,omitempty"`
	// MoonPhase is the fraction of the synodic cycle at the current time,
	// in [0,1): 0 = new moon, 0.25 = first quarter, 0.5 = full moon,
	// 0.75 = last quarter. It is computed locally (Open-Meteo does not
	// provide it). It is nil when the persisted snapshot predates the field.
	MoonPhase *float64 `json:"moonPhase,omitempty"`
	// MoonIllumination is the illuminated fraction of the lunar disk in
	// percent (0-100), derived from MoonPhase. It is nil when the persisted
	// snapshot predates the field.
	MoonIllumination *float64 `json:"moonIllumination,omitempty"`
}

type WeatherHourlyPoint struct {
	Time                string  `json:"time"`
	Temperature         float64 `json:"temperature"`
	ApparentTemp        float64 `json:"apparentTemperature"`
	RelativeHumidity    float64 `json:"relativeHumidity"`
	PrecipitationChance float64 `json:"precipitationProbability"`
	WeatherCode         int     `json:"weatherCode"`
	IsDay               bool    `json:"isDay"`
	WindSpeed           float64 `json:"windSpeed"`
}

type WeatherDay struct {
	Date                string  `json:"date"`
	WeatherCode         int     `json:"weatherCode"`
	TemperatureMaximum  float64 `json:"temperatureMaximum"`
	TemperatureMinimum  float64 `json:"temperatureMinimum"`
	PrecipitationChance float64 `json:"precipitationProbability"`
	Sunrise             string  `json:"sunrise,omitempty"`
	Sunset              string  `json:"sunset,omitempty"`
}

// WeatherState is both durable state and the versioned snapshot contract.
// Consumers must use the timestamps instead of inferring freshness from the
// process lifetime. Current data remains available after a failed refresh.
type WeatherState struct {
	SchemaVersion int                  `json:"schemaVersion"`
	Provider      string               `json:"provider"`
	Status        string               `json:"status"`
	Units         string               `json:"units"`
	Location      WeatherLocation      `json:"location"`
	Locations     []WeatherLocation    `json:"locations"`
	FetchedAt     int64                `json:"fetchedAt,omitempty"`
	NextRefreshAt int64                `json:"nextRefreshAt,omitempty"`
	StaleAt       int64                `json:"staleAt,omitempty"`
	LastAttemptAt int64                `json:"lastAttemptAt,omitempty"`
	Error         string               `json:"error,omitempty"`
	Current       *WeatherCurrent      `json:"current,omitempty"`
	AirQuality    *WeatherAirQuality   `json:"airQuality,omitempty"`
	Hourly        []WeatherHourlyPoint `json:"hourly"`
	Daily         []WeatherDay         `json:"daily"`
}

// cachedWeather is an in-memory snapshot of one location's forecast, used to
// paint the window instantly when the user switches back to a city.
type cachedWeather struct {
	Units      string
	Current    *WeatherCurrent
	AirQuality *WeatherAirQuality
	Hourly     []WeatherHourlyPoint
	Daily      []WeatherDay
	FetchedAt  int64
	StaleAt    int64
}

type WeatherForecast struct {
	Timezone   string
	Current    *WeatherCurrent
	AirQuality *WeatherAirQuality
	Hourly     []WeatherHourlyPoint
	Daily      []WeatherDay
}

type WeatherProvider interface {
	Forecast(context.Context, WeatherLocation, string) (WeatherForecast, error)
	Search(context.Context, string, string, int) ([]WeatherLocation, error)
	Summaries(context.Context, []WeatherLocation, string) (map[string]WeatherLocationSummary, error)
}

type OpenMeteoProvider struct {
	client        *http.Client
	forecastURL   string
	geocodingURL  string
	airQualityURL string
}

func defaultWeatherState() WeatherState {
	location := WeatherLocation{
		ID:          "legacy:changsha",
		Name:        "长沙",
		Admin1:      "湖南",
		Country:     "中国",
		CountryCode: "CN",
		Latitude:    28.2282,
		Longitude:   112.9388,
		Timezone:    "Asia/Shanghai",
	}
	return WeatherState{
		SchemaVersion: weatherSchemaVersion,
		Provider:      weatherProviderName,
		Status:        weatherStatusIdle,
		Units:         weatherUnitsMetric,
		Location:      location,
		Locations:     []WeatherLocation{location},
		Hourly:        []WeatherHourlyPoint{},
		Daily:         []WeatherDay{},
	}
}

func normalizeWeatherState(state *WeatherState) {
	// An explicit empty list is a saved user choice, unlike a legacy missing list.
	if state.SchemaVersion == weatherSchemaVersion && state.Locations != nil &&
		len(state.Locations) == 0 && state.Location.ID == "" {
		units := state.Units
		if units != weatherUnitsMetric && units != weatherUnitsImperial {
			units = weatherUnitsMetric
		}
		*state = WeatherState{SchemaVersion: weatherSchemaVersion, Provider: weatherProviderName,
			Units: units, Status: weatherStatusIdle, Locations: []WeatherLocation{},
			Hourly: []WeatherHourlyPoint{}, Daily: []WeatherDay{}}
		return
	}
	if state.SchemaVersion == 0 {
		state.SchemaVersion = weatherSchemaVersion
	}
	if state.Provider == "" {
		state.Provider = weatherProviderName
	}
	if state.Units != weatherUnitsMetric && state.Units != weatherUnitsImperial {
		state.Units = weatherUnitsMetric
	}
	if !validWeatherLocation(state.Location) {
		fallback := defaultWeatherState()
		state.Location = fallback.Location
	}
	if len(state.Locations) == 0 {
		state.Locations = []WeatherLocation{state.Location}
	}
	found := false
	for _, location := range state.Locations {
		if location.ID == state.Location.ID {
			found = true
			break
		}
	}
	if !found {
		state.Locations = append([]WeatherLocation{state.Location}, state.Locations...)
	}
	if state.Hourly == nil {
		state.Hourly = []WeatherHourlyPoint{}
	}
	if state.Daily == nil {
		state.Daily = []WeatherDay{}
	}
	// A persisted loading marker means the process stopped mid-request.
	if state.Status == weatherStatusLoading {
		state.Status = weatherStatusIdle
	}
	if state.Current != nil {
		state.Status = weatherStatusReady
	} else if state.Status != weatherStatusError {
		state.Status = weatherStatusIdle
	}
}

func validWeatherLocation(location WeatherLocation) bool {
	return strings.TrimSpace(location.Name) != "" &&
		!math.IsNaN(location.Latitude) && !math.IsInf(location.Latitude, 0) &&
		!math.IsNaN(location.Longitude) && !math.IsInf(location.Longitude, 0) &&
		location.Latitude >= -90 && location.Latitude <= 90 &&
		location.Longitude >= -180 && location.Longitude <= 180
}

func normalizeWeatherLocation(location WeatherLocation) (WeatherLocation, error) {
	location.Name = strings.TrimSpace(location.Name)
	location.Admin1 = strings.TrimSpace(location.Admin1)
	location.Country = strings.TrimSpace(location.Country)
	location.CountryCode = strings.ToUpper(strings.TrimSpace(location.CountryCode))
	location.Timezone = strings.TrimSpace(location.Timezone)
	if !validWeatherLocation(location) {
		return WeatherLocation{}, errors.New("invalid weather location")
	}
	if location.ID == "" {
		location.ID = fmt.Sprintf("manual:%.5f,%.5f", location.Latitude, location.Longitude)
	}
	return location, nil
}

func newOpenMeteoProvider() *OpenMeteoProvider {
	return &OpenMeteoProvider{
		client:        &http.Client{Timeout: weatherRequestTimeout},
		forecastURL:   "https://api.open-meteo.com/v1/forecast",
		geocodingURL:  "https://geocoding-api.open-meteo.com/v1/search",
		airQualityURL: "https://air-quality-api.open-meteo.com/v1/air-quality",
	}
}

func (provider *OpenMeteoProvider) getJSON(ctx context.Context, endpoint string, target any) error {
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return err
	}
	request.Header.Set("Accept", "application/json")
	request.Header.Set("User-Agent", "NextKde/0.1 (+https://github.com/SuceV587/NextKde)")
	response, err := provider.client.Do(request)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		_, _ = io.Copy(io.Discard, io.LimitReader(response.Body, 4096))
		return fmt.Errorf("weather provider returned HTTP %d", response.StatusCode)
	}
	decoder := json.NewDecoder(io.LimitReader(response.Body, weatherMaximumBodySize))
	if err := decoder.Decode(target); err != nil {
		return fmt.Errorf("decode weather response: %w", err)
	}
	return nil
}

type openMeteoForecastPayload struct {
	Timezone string `json:"timezone"`
	Current  struct {
		Time             string   `json:"time"`
		Temperature      float64  `json:"temperature_2m"`
		RelativeHumidity float64  `json:"relative_humidity_2m"`
		ApparentTemp     float64  `json:"apparent_temperature"`
		IsDay            int      `json:"is_day"`
		WeatherCode      int      `json:"weather_code"`
		WindSpeed        float64  `json:"wind_speed_10m"`
		WindDirection    float64  `json:"wind_direction_10m"`
		WindGust         *float64 `json:"wind_gusts_10m"`
		UvIndex          *float64 `json:"uv_index"`
		Visibility       *float64 `json:"visibility"`
		Pressure         *float64 `json:"pressure_msl"`
	} `json:"current"`
	Hourly struct {
		Time                []string  `json:"time"`
		Temperature         []float64 `json:"temperature_2m"`
		ApparentTemp        []float64 `json:"apparent_temperature"`
		RelativeHumidity    []float64 `json:"relative_humidity_2m"`
		PrecipitationChance []float64 `json:"precipitation_probability"`
		WeatherCode         []int     `json:"weather_code"`
		IsDay               []int     `json:"is_day"`
		WindSpeed           []float64 `json:"wind_speed_10m"`
	} `json:"hourly"`
	Daily struct {
		Time                []string  `json:"time"`
		WeatherCode         []int     `json:"weather_code"`
		TemperatureMaximum  []float64 `json:"temperature_2m_max"`
		TemperatureMinimum  []float64 `json:"temperature_2m_min"`
		PrecipitationChance []float64 `json:"precipitation_probability_max"`
		Sunrise             []string  `json:"sunrise"`
		Sunset              []string  `json:"sunset"`
	} `json:"daily"`
}

func shortestLength(lengths ...int) int {
	if len(lengths) == 0 {
		return 0
	}
	result := lengths[0]
	for _, length := range lengths[1:] {
		if length < result {
			result = length
		}
	}
	return result
}

func (provider *OpenMeteoProvider) Forecast(ctx context.Context, location WeatherLocation, units string) (WeatherForecast, error) {
	if !validWeatherLocation(location) {
		return WeatherForecast{}, errors.New("invalid weather location")
	}
	values := url.Values{
		"latitude":      {fmt.Sprintf("%.6f", location.Latitude)},
		"longitude":     {fmt.Sprintf("%.6f", location.Longitude)},
		"current":       {"temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,wind_speed_10m,wind_direction_10m,wind_gusts_10m,uv_index,visibility,pressure_msl"},
		"hourly":        {"temperature_2m,apparent_temperature,relative_humidity_2m,precipitation_probability,weather_code,is_day,wind_speed_10m"},
		"daily":         {"weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset"},
		"timezone":      {"auto"},
		"forecast_days": {"7"},
	}
	if units == weatherUnitsImperial {
		values.Set("temperature_unit", "fahrenheit")
		values.Set("wind_speed_unit", "mph")
		values.Set("precipitation_unit", "inch")
	} else {
		values.Set("temperature_unit", "celsius")
		values.Set("wind_speed_unit", "kmh")
		values.Set("precipitation_unit", "mm")
	}

	var payload openMeteoForecastPayload
	if err := provider.getJSON(ctx, provider.forecastURL+"?"+values.Encode(), &payload); err != nil {
		return WeatherForecast{}, err
	}
	if payload.Current.Time == "" {
		return WeatherForecast{}, errors.New("weather response has no current conditions")
	}

	phase, illumination := moonPhaseAt(time.Now().UTC())
	forecast := WeatherForecast{
		Timezone: payload.Timezone,
		Current: &WeatherCurrent{
			Time:             payload.Current.Time,
			Temperature:      payload.Current.Temperature,
			ApparentTemp:     payload.Current.ApparentTemp,
			RelativeHumidity: payload.Current.RelativeHumidity,
			IsDay:            payload.Current.IsDay == 1,
			WeatherCode:      payload.Current.WeatherCode,
			WindSpeed:        payload.Current.WindSpeed,
			WindDirection:    payload.Current.WindDirection,
			WindGust:         payload.Current.WindGust,
			UvIndex:          payload.Current.UvIndex,
			Visibility:       payload.Current.Visibility,
			Pressure:         payload.Current.Pressure,
			MoonPhase:        &phase,
			MoonIllumination: &illumination,
		},
		Hourly: []WeatherHourlyPoint{},
		Daily:  []WeatherDay{},
	}

	hourlyCount := shortestLength(
		len(payload.Hourly.Time),
		len(payload.Hourly.Temperature),
		len(payload.Hourly.ApparentTemp),
		len(payload.Hourly.RelativeHumidity),
		len(payload.Hourly.PrecipitationChance),
		len(payload.Hourly.WeatherCode),
		len(payload.Hourly.IsDay),
		len(payload.Hourly.WindSpeed),
	)
	if hourlyCount > 48 {
		hourlyCount = 48
	}
	for index := 0; index < hourlyCount; index++ {
		forecast.Hourly = append(forecast.Hourly, WeatherHourlyPoint{
			Time:                payload.Hourly.Time[index],
			Temperature:         payload.Hourly.Temperature[index],
			ApparentTemp:        payload.Hourly.ApparentTemp[index],
			RelativeHumidity:    payload.Hourly.RelativeHumidity[index],
			PrecipitationChance: payload.Hourly.PrecipitationChance[index],
			WeatherCode:         payload.Hourly.WeatherCode[index],
			IsDay:               payload.Hourly.IsDay[index] == 1,
			WindSpeed:           payload.Hourly.WindSpeed[index],
		})
	}

	dailyCount := shortestLength(
		len(payload.Daily.Time),
		len(payload.Daily.WeatherCode),
		len(payload.Daily.TemperatureMaximum),
		len(payload.Daily.TemperatureMinimum),
		len(payload.Daily.PrecipitationChance),
		len(payload.Daily.Sunrise),
		len(payload.Daily.Sunset),
	)
	if dailyCount > 7 {
		dailyCount = 7
	}
	for index := 0; index < dailyCount; index++ {
		forecast.Daily = append(forecast.Daily, WeatherDay{
			Date:                payload.Daily.Time[index],
			WeatherCode:         payload.Daily.WeatherCode[index],
			TemperatureMaximum:  payload.Daily.TemperatureMaximum[index],
			TemperatureMinimum:  payload.Daily.TemperatureMinimum[index],
			PrecipitationChance: payload.Daily.PrecipitationChance[index],
			Sunrise:             payload.Daily.Sunrise[index],
			Sunset:              payload.Daily.Sunset[index],
		})
	}
	// Air quality is best-effort: a failed or missing reading leaves AirQuality
	// nil instead of failing the refresh, and the previous reading stays in
	// place until a new one arrives.
	if airQuality, airQualityErr := provider.AirQuality(ctx, location); airQualityErr == nil {
		forecast.AirQuality = airQuality
	}
	return forecast, nil
}

// openMeteoSummaryPayload is one element of a multi-location Open-Meteo
// response: current conditions plus today's range, nothing else.
type openMeteoSummaryPayload struct {
	Latitude  float64 `json:"latitude"`
	Longitude float64 `json:"longitude"`
	Timezone  string  `json:"timezone"`
	Current   struct {
		Time        string  `json:"time"`
		Temperature float64 `json:"temperature_2m"`
		IsDay       int     `json:"is_day"`
		WeatherCode int     `json:"weather_code"`
	} `json:"current"`
	Daily struct {
		TemperatureMaximum []float64 `json:"temperature_2m_max"`
		TemperatureMinimum []float64 `json:"temperature_2m_min"`
	} `json:"daily"`
}

// Summaries fetches a compact per-city snapshot for the sidebar cards in one
// batched Open-Meteo request. Results are keyed by location ID; elements are
// matched by request order, and any element whose echoed coordinates do not
// line up with the requested location is skipped rather than trusted.
func (provider *OpenMeteoProvider) Summaries(ctx context.Context, locations []WeatherLocation, units string) (map[string]WeatherLocationSummary, error) {
	if len(locations) > 20 {
		locations = locations[:20]
	}
	if len(locations) == 0 {
		return map[string]WeatherLocationSummary{}, nil
	}
	latitudes := make([]string, len(locations))
	longitudes := make([]string, len(locations))
	for index, location := range locations {
		latitudes[index] = fmt.Sprintf("%.6f", location.Latitude)
		longitudes[index] = fmt.Sprintf("%.6f", location.Longitude)
	}
	values := url.Values{
		"latitude":      {strings.Join(latitudes, ",")},
		"longitude":     {strings.Join(longitudes, ",")},
		"current":       {"temperature_2m,is_day,weather_code"},
		"daily":         {"temperature_2m_max,temperature_2m_min"},
		"forecast_days": {"1"},
		"timezone":      {"auto"},
	}
	if units == weatherUnitsImperial {
		values.Set("temperature_unit", "fahrenheit")
	}

	var payload json.RawMessage
	if err := provider.getJSON(ctx, provider.forecastURL+"?"+values.Encode(), &payload); err != nil {
		return nil, err
	}
	// Open-Meteo returns an array for multiple coordinates and a bare object
	// for a single one.
	var payloads []openMeteoSummaryPayload
	if err := json.Unmarshal(payload, &payloads); err != nil {
		var single openMeteoSummaryPayload
		if err := json.Unmarshal(payload, &single); err != nil {
			return nil, fmt.Errorf("decode weather summary response: %w", err)
		}
		payloads = []openMeteoSummaryPayload{single}
	}
	summaries := make(map[string]WeatherLocationSummary, len(locations))
	for index, item := range payloads {
		if index >= len(locations) {
			break
		}
		location := locations[index]
		if math.Abs(item.Latitude-location.Latitude) > 0.1 ||
			math.Abs(item.Longitude-location.Longitude) > 0.1 {
			continue
		}
		summary := WeatherLocationSummary{
			Time:        item.Current.Time,
			Temperature: item.Current.Temperature,
			WeatherCode: item.Current.WeatherCode,
			IsDay:       item.Current.IsDay == 1,
		}
		if shortestLength(len(item.Daily.TemperatureMaximum), len(item.Daily.TemperatureMinimum)) > 0 {
			summary.TempHigh = item.Daily.TemperatureMaximum[0]
			summary.TempLow = item.Daily.TemperatureMinimum[0]
		}
		summaries[location.ID] = summary
	}
	return summaries, nil
}

type openMeteoAirQualityPayload struct {
	Current struct {
		Time  string   `json:"time"`
		UsAqi *float64 `json:"us_aqi"`
	} `json:"current"`
}

// AirQuality fetches the current US AQI reading for one location. A missing
// reading (us_aqi absent) is not an error: the caller gets (nil, nil) and the
// UI simply shows no air quality data.
func (provider *OpenMeteoProvider) AirQuality(ctx context.Context, location WeatherLocation) (*WeatherAirQuality, error) {
	if !validWeatherLocation(location) {
		return nil, errors.New("invalid weather location")
	}
	values := url.Values{
		"latitude":  {fmt.Sprintf("%.6f", location.Latitude)},
		"longitude": {fmt.Sprintf("%.6f", location.Longitude)},
		"current":   {"us_aqi"},
	}
	var payload openMeteoAirQualityPayload
	if err := provider.getJSON(ctx, provider.airQualityURL+"?"+values.Encode(), &payload); err != nil {
		return nil, err
	}
	if payload.Current.UsAqi == nil {
		return nil, nil
	}
	aqi := *payload.Current.UsAqi
	return &WeatherAirQuality{
		Time:     payload.Current.Time,
		UsAqi:    &aqi,
		Category: usAqiCategory(aqi),
	}, nil
}

// moonSynodicMonth is the mean synodic month in days.
const moonSynodicMonth = 29.530588853

// moonEpoch is a known new moon: 2000-01-06 18:14 UTC.
var moonEpoch = time.Date(2000, 1, 6, 18, 14, 0, 0, time.UTC)

// moonPhaseAt returns the fraction of the synodic cycle in [0,1) and the
// illuminated disk percentage for the given instant, computed with the
// mean-synodic-month approximation.
func moonPhaseAt(when time.Time) (phase float64, illumination float64) {
	days := when.Sub(moonEpoch).Hours() / 24
	phase = math.Mod(days/moonSynodicMonth, 1)
	if phase < 0 {
		phase += 1
	}
	illumination = (1 - math.Cos(2*math.Pi*phase)) / 2 * 100
	return phase, illumination
}

// usAqiCategory maps a US EPA AQI reading to its band name. Negative values
// are clamped to zero so malformed readings still land in "Good".
func usAqiCategory(aqi float64) string {
	if aqi < 0 {
		aqi = 0
	}
	switch {
	case aqi <= 50:
		return "Good"
	case aqi <= 100:
		return "Moderate"
	case aqi <= 150:
		return "Unhealthy for Sensitive Groups"
	case aqi <= 200:
		return "Unhealthy"
	case aqi <= 300:
		return "Very Unhealthy"
	default:
		return "Hazardous"
	}
}

type openMeteoSearchPayload struct {
	Results []struct {
		ID          int64   `json:"id"`
		Name        string  `json:"name"`
		Latitude    float64 `json:"latitude"`
		Longitude   float64 `json:"longitude"`
		Timezone    string  `json:"timezone"`
		CountryCode string  `json:"country_code"`
		Country     string  `json:"country"`
		Admin1      string  `json:"admin1"`
	} `json:"results"`
}

func (provider *OpenMeteoProvider) Search(ctx context.Context, query, language string, count int) ([]WeatherLocation, error) {
	query = strings.TrimSpace(query)
	if utf8.RuneCountInString(query) < 2 || utf8.RuneCountInString(query) > 128 {
		return nil, errors.New("weather search query must contain 2 to 128 characters")
	}
	if count < 1 {
		count = 1
	} else if count > 20 {
		count = 20
	}
	language = strings.TrimSpace(language)
	if language == "" || len(language) > 16 {
		language = "en"
	}
	values := url.Values{
		"name":     {query},
		"count":    {fmt.Sprintf("%d", count)},
		"language": {language},
		"format":   {"json"},
	}
	var payload openMeteoSearchPayload
	if err := provider.getJSON(ctx, provider.geocodingURL+"?"+values.Encode(), &payload); err != nil {
		return nil, err
	}
	locations := make([]WeatherLocation, 0, len(payload.Results))
	for _, result := range payload.Results {
		location := WeatherLocation{
			ID:          fmt.Sprintf("open-meteo:%d", result.ID),
			Name:        strings.TrimSpace(result.Name),
			Admin1:      strings.TrimSpace(result.Admin1),
			Country:     strings.TrimSpace(result.Country),
			CountryCode: strings.ToUpper(strings.TrimSpace(result.CountryCode)),
			Latitude:    result.Latitude,
			Longitude:   result.Longitude,
			Timezone:    strings.TrimSpace(result.Timezone),
		}
		if validWeatherLocation(location) {
			locations = append(locations, location)
		}
	}
	return locations, nil
}

func weatherErrorMessage(err error) string {
	if err == nil {
		return ""
	}
	message := strings.TrimSpace(err.Error())
	if len(message) > 240 {
		message = message[:240]
	}
	return message
}

// weatherCacheKey scopes snapshots by location and units so metric and imperial
// readings of the same city are never mixed.
func weatherCacheKey(locationID, units string) string {
	return locationID + "|" + units
}

// rememberWeatherLocked stores the current weather snapshot for the active
// location. Caller holds s.mu.
func (s *Service) rememberWeatherLocked(locationID, units string) {
	if locationID == "" {
		return
	}
	weather := &s.state.Weather
	if weather.Current == nil {
		return
	}
	if s.weatherCache == nil {
		s.weatherCache = make(map[string]cachedWeather, 8)
	}
	key := weatherCacheKey(locationID, units)
	s.weatherCache[key] = cachedWeather{
		Units:      units,
		Current:    weather.Current,
		AirQuality: weather.AirQuality,
		Hourly:     weather.Hourly,
		Daily:      weather.Daily,
		FetchedAt:  weather.FetchedAt,
		StaleAt:    weather.StaleAt,
	}
	for len(s.weatherCache) > maxCachedWeather {
		for stale := range s.weatherCache {
			if stale != key {
				delete(s.weatherCache, stale)
				break
			}
		}
	}
}

// applyCachedWeatherLocked restores the cached snapshot for the location the
// user just selected. It reports whether content was restored. Caller holds s.mu.
func (s *Service) applyCachedWeatherLocked() bool {
	if len(s.weatherCache) == 0 {
		return false
	}
	weather := &s.state.Weather
	cached, ok := s.weatherCache[weatherCacheKey(weather.Location.ID, weather.Units)]
	if !ok || cached.Current == nil {
		return false
	}
	weather.Current = cached.Current
	weather.AirQuality = cached.AirQuality
	weather.Hourly = cached.Hourly
	weather.Daily = cached.Daily
	weather.FetchedAt = cached.FetchedAt
	weather.StaleAt = cached.StaleAt
	return true
}

func (s *Service) setWeatherLocation(location WeatherLocation) error {
	normalized, err := normalizeWeatherLocation(location)
	if err != nil {
		return err
	}
	s.mu.Lock()
	s.weatherRequestSerial++
	s.weatherFailStreak = 0
	s.state.Weather.Location = normalized
	found := false
	for index := range s.state.Weather.Locations {
		if s.state.Weather.Locations[index].ID == normalized.ID {
			s.state.Weather.Locations[index] = normalized
			found = true
			break
		}
	}
	if !found {
		s.state.Weather.Locations = append(s.state.Weather.Locations, normalized)
	}
	if len(s.state.Weather.Locations) > 20 {
		s.state.Weather.Locations = s.state.Weather.Locations[len(s.state.Weather.Locations)-20:]
	}
	s.state.Weather.NextRefreshAt = 0
	s.state.Weather.Error = ""
	if s.applyCachedWeatherLocked() {
		// The user already visited this city: publish its snapshot right away and
		// refresh in the background. Content stays on screen while loading.
		s.state.Weather.Status = weatherStatusReady
	} else {
		s.state.Weather.Current = nil
		s.state.Weather.AirQuality = nil
		s.state.Weather.Hourly = []WeatherHourlyPoint{}
		s.state.Weather.Daily = []WeatherDay{}
		s.state.Weather.FetchedAt = 0
		s.state.Weather.StaleAt = 0
		// Announce the fetch before it starts so the UI can show its loading
		// feedback instead of a blank, wiped snapshot.
		s.state.Weather.Status = weatherStatusLoading
		s.state.Weather.LastAttemptAt = time.Now().UnixMilli()
	}
	s.mu.Unlock()
	s.persist()
	s.publishWeather()
	s.startWeatherRefresh(true)
	return nil
}

// removeWeatherLocation persists the list and invalidates a deleted city's in-flight forecast.
func (s *Service) removeWeatherLocation(id string) error {
	if strings.TrimSpace(id) == "" {
		return errors.New("city id is required")
	}
	s.mu.Lock()
	weather := &s.state.Weather
	index := -1
	for i, location := range weather.Locations {
		if location.ID == id {
			index = i
			break
		}
	}
	if index < 0 {
		s.mu.Unlock()
		return nil
	} // Repeating an acknowledged deletion is safe.
	remaining := make([]WeatherLocation, 0, len(weather.Locations)-1)
	remaining = append(remaining, weather.Locations[:index]...)
	remaining = append(remaining, weather.Locations[index+1:]...)
	weather.Locations = remaining
	delete(s.weatherCache, weatherCacheKey(id, weatherUnitsMetric))
	delete(s.weatherCache, weatherCacheKey(id, weatherUnitsImperial))
	selected := weather.Location.ID == id
	if selected {
		s.weatherRequestSerial++
		s.weatherFailStreak = 0
		units := weather.Units
		*weather = WeatherState{SchemaVersion: weatherSchemaVersion, Provider: weatherProviderName,
			Units: units, Status: weatherStatusIdle, Locations: remaining,
			Hourly: []WeatherHourlyPoint{}, Daily: []WeatherDay{}}
		if len(remaining) > 0 {
			weather.Location = remaining[min(index, len(remaining)-1)]
			if s.applyCachedWeatherLocked() {
				weather.Status = weatherStatusReady
			}
		}
	}
	refresh := selected && len(remaining) > 0
	s.mu.Unlock()
	s.persist()
	s.publishWeather()
	if refresh {
		s.startWeatherRefresh(true)
	}
	return nil
}

func (s *Service) setWeatherUnits(units string) error {
	if units != weatherUnitsMetric && units != weatherUnitsImperial {
		return errors.New("weather units must be metric or imperial")
	}
	s.mu.Lock()
	if s.state.Weather.Units == units {
		s.mu.Unlock()
		return nil
	}
	s.weatherRequestSerial++
	s.weatherFailStreak = 0
	s.state.Weather.Units = units
	s.state.Weather.Status = weatherStatusIdle
	s.state.Weather.Error = ""
	s.state.Weather.Current = nil
	s.state.Weather.Hourly = []WeatherHourlyPoint{}
	s.state.Weather.Daily = []WeatherDay{}
	s.state.Weather.FetchedAt = 0
	s.state.Weather.NextRefreshAt = 0
	s.state.Weather.StaleAt = 0
	s.mu.Unlock()
	s.persist()
	s.publishWeather()
	s.startWeatherRefresh(true)
	return nil
}

func (s *Service) startWeatherRefresh(force bool) bool {
	now := time.Now()
	s.mu.Lock()
	// Normalize persisted state once at startup. Doing it here clears a live
	// loading marker and allows every tick to supersede the in-flight request.
	weather := &s.state.Weather
	if !validWeatherLocation(weather.Location) {
		s.mu.Unlock()
		return false
	}
	// A user-initiated refresh (force) may supersede an in-flight fetch: the
	// serial bump below invalidates the older response. Without this, switching
	// cities while a fetch is running was silently dropped and the window sat
	// blank until the previous city's request finished.
	if weather.Status == weatherStatusLoading && !force {
		s.mu.Unlock()
		return false
	}
	// NextRefreshAt gates automatic refreshes regardless of whether cached
	// conditions exist: after a success it is +1h, after a failure it is the
	// exponential backoff. A user-initiated refresh (force) bypasses it, and
	// location/units changes reset it to 0.
	if !force && weather.NextRefreshAt > now.UnixMilli() {
		s.mu.Unlock()
		return false
	}
	s.weatherRequestSerial++
	serial := s.weatherRequestSerial
	location := weather.Location
	units := weather.Units
	weather.Status = weatherStatusLoading
	weather.LastAttemptAt = now.UnixMilli()
	weather.Error = ""
	provider := s.weatherProvider
	s.mu.Unlock()

	s.persist()
	s.publishWeather()
	go s.fetchWeather(serial, provider, location, units)
	return true
}

// weatherBackoff returns the delay before the next automatic refresh after
// the given number of consecutive failures: 1min, 2min, 4min, ... capped at
// 30min. The shift is clamped so a long outage can never overflow.
func weatherBackoff(streak int) time.Duration {
	if streak < 1 {
		streak = 1
	}
	shift := streak - 1
	if shift > 9 {
		shift = 9
	}
	backoff := weatherBackoffBase << shift
	if backoff > weatherBackoffMax {
		backoff = weatherBackoffMax
	}
	return backoff
}

// weatherLocationsSnapshot copies the saved location list under the state
// lock so batched provider requests never read it while it mutates.
func (s *Service) weatherLocationsSnapshot() []WeatherLocation {
	s.mu.Lock()
	locations := make([]WeatherLocation, len(s.state.Weather.Locations))
	copy(locations, s.state.Weather.Locations)
	s.mu.Unlock()
	return locations
}

func (s *Service) fetchWeather(serial uint64, provider WeatherProvider, location WeatherLocation, units string) {
	ctx, cancel := context.WithTimeout(context.Background(), weatherRequestTimeout)
	defer cancel()
	forecast, err := provider.Forecast(ctx, location, units)
	now := time.Now()

	summaries := map[string]WeatherLocationSummary{}
	if err == nil && forecast.Current != nil {
		// Sidebar summaries are best-effort: a failed batch request leaves the
		// previous summaries in place instead of failing the refresh.
		if fetched, summaryErr := provider.Summaries(ctx, s.weatherLocationsSnapshot(), units); summaryErr == nil {
			summaries = fetched
		}
		// The selected location always shows the freshly fetched forecast, so
		// its summary comes from the same response rather than the batch.
		selected := WeatherLocationSummary{
			Time:        forecast.Current.Time,
			Temperature: forecast.Current.Temperature,
			WeatherCode: forecast.Current.WeatherCode,
			IsDay:       forecast.Current.IsDay,
		}
		if len(forecast.Daily) > 0 {
			selected.TempHigh = forecast.Daily[0].TemperatureMaximum
			selected.TempLow = forecast.Daily[0].TemperatureMinimum
		}
		summaries[location.ID] = selected
	}

	s.mu.Lock()
	if serial != s.weatherRequestSerial {
		s.mu.Unlock()
		return
	}
	weather := &s.state.Weather
	unchanged := false
	if err != nil {
		s.weatherFailStreak++
		previousStatus, previousError := weather.Status, weather.Error
		weather.Error = weatherErrorMessage(err)
		if weather.Current != nil {
			weather.Status = weatherStatusReady
		} else {
			weather.Status = weatherStatusError
		}
		// Back off the next automatic retry exponentially. Persisting the new
		// NextRefreshAt is what makes the backoff durable across restarts.
		weather.NextRefreshAt = now.Add(weatherBackoff(s.weatherFailStreak)).UnixMilli()
		// The publish only tells consumers to re-read the weather snapshot; if
		// the user-visible fields did not change (still failing with the same
		// status and message), skip the broadcast wake. Persist still runs so
		// the growing backoff survives restarts.
		unchanged = weather.Status == previousStatus && weather.Error == previousError
	} else {
		s.weatherFailStreak = 0
		weather.Status = weatherStatusReady
		weather.Error = ""
		weather.Current = forecast.Current
		if forecast.AirQuality != nil {
			weather.AirQuality = forecast.AirQuality
		}
		weather.Hourly = forecast.Hourly
		weather.Daily = forecast.Daily
		weather.FetchedAt = now.UnixMilli()
		weather.NextRefreshAt = now.Add(weatherRefreshInterval).UnixMilli()
		weather.StaleAt = now.Add(weatherStaleInterval).UnixMilli()
		if weather.Location.Timezone == "" && forecast.Timezone != "" {
			weather.Location.Timezone = forecast.Timezone
		}
		for index := range weather.Locations {
			if summary, ok := summaries[weather.Locations[index].ID]; ok {
				weather.Locations[index].Summary = &summary
			}
		}
	}
	if err == nil && weather.Current != nil {
		s.rememberWeatherLocked(weather.Location.ID, weather.Units)
	}
	s.mu.Unlock()
	s.persist()
	if !unchanged {
		s.publishWeather()
	}
}

func (s *Service) searchWeather(query, language string, count int) ([]WeatherLocation, error) {
	ctx, cancel := context.WithTimeout(context.Background(), weatherRequestTimeout)
	defer cancel()
	return s.weatherProvider.Search(ctx, query, language, count)
}
