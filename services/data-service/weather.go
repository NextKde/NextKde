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
)

type WeatherLocation struct {
	ID          string  `json:"id"`
	Name        string  `json:"name"`
	Admin1      string  `json:"admin1,omitempty"`
	Country     string  `json:"country,omitempty"`
	CountryCode string  `json:"countryCode,omitempty"`
	Latitude    float64 `json:"latitude"`
	Longitude   float64 `json:"longitude"`
	Timezone    string  `json:"timezone,omitempty"`
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
	Hourly        []WeatherHourlyPoint `json:"hourly"`
	Daily         []WeatherDay         `json:"daily"`
}

type WeatherForecast struct {
	Timezone string
	Current  *WeatherCurrent
	Hourly   []WeatherHourlyPoint
	Daily    []WeatherDay
}

type WeatherProvider interface {
	Forecast(context.Context, WeatherLocation, string) (WeatherForecast, error)
	Search(context.Context, string, string, int) ([]WeatherLocation, error)
}

type OpenMeteoProvider struct {
	client       *http.Client
	forecastURL  string
	geocodingURL string
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
		client:       &http.Client{Timeout: weatherRequestTimeout},
		forecastURL:  "https://api.open-meteo.com/v1/forecast",
		geocodingURL: "https://geocoding-api.open-meteo.com/v1/search",
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
		Time             string  `json:"time"`
		Temperature      float64 `json:"temperature_2m"`
		RelativeHumidity float64 `json:"relative_humidity_2m"`
		ApparentTemp     float64 `json:"apparent_temperature"`
		IsDay            int     `json:"is_day"`
		WeatherCode      int     `json:"weather_code"`
		WindSpeed        float64 `json:"wind_speed_10m"`
		WindDirection    float64 `json:"wind_direction_10m"`
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
		"current":       {"temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,wind_speed_10m,wind_direction_10m"},
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
	return forecast, nil
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

func (s *Service) setWeatherLocation(location WeatherLocation) error {
	normalized, err := normalizeWeatherLocation(location)
	if err != nil {
		return err
	}
	s.mu.Lock()
	s.weatherRequestSerial++
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
	normalizeWeatherState(&s.state.Weather)
	weather := &s.state.Weather
	if weather.Status == weatherStatusLoading {
		s.mu.Unlock()
		return false
	}
	if !force && weather.Current != nil && weather.NextRefreshAt > now.UnixMilli() {
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

func (s *Service) fetchWeather(serial uint64, provider WeatherProvider, location WeatherLocation, units string) {
	ctx, cancel := context.WithTimeout(context.Background(), weatherRequestTimeout)
	defer cancel()
	forecast, err := provider.Forecast(ctx, location, units)
	now := time.Now()

	s.mu.Lock()
	if serial != s.weatherRequestSerial {
		s.mu.Unlock()
		return
	}
	weather := &s.state.Weather
	if err != nil {
		weather.Error = weatherErrorMessage(err)
		if weather.Current != nil {
			weather.Status = weatherStatusReady
		} else {
			weather.Status = weatherStatusError
		}
	} else {
		weather.Status = weatherStatusReady
		weather.Error = ""
		weather.Current = forecast.Current
		weather.Hourly = forecast.Hourly
		weather.Daily = forecast.Daily
		weather.FetchedAt = now.UnixMilli()
		weather.NextRefreshAt = now.Add(weatherRefreshInterval).UnixMilli()
		weather.StaleAt = now.Add(weatherStaleInterval).UnixMilli()
		if weather.Location.Timezone == "" && forecast.Timezone != "" {
			weather.Location.Timezone = forecast.Timezone
		}
	}
	s.mu.Unlock()
	s.persist()
	s.publishWeather()
}

func (s *Service) searchWeather(query, language string, count int) ([]WeatherLocation, error) {
	ctx, cancel := context.WithTimeout(context.Background(), weatherRequestTimeout)
	defer cancel()
	return s.weatherProvider.Search(ctx, query, language, count)
}
