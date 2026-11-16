package main

import (
	"bufio"
	"encoding/json"
	"net"
	"os"
	"time"
)

type DataRequest struct {
	Version   int                    `json:"version"`
	RequestID string                 `json:"requestId"`
	Operation string                 `json:"operation"`
	Payload   map[string]interface{} `json:"payload"`
}

type DataResponse struct {
	Version   int         `json:"version"`
	RequestID string      `json:"requestId,omitempty"`
	OK        bool        `json:"ok"`
	Result    interface{} `json:"result,omitempty"`
	Error     *DataError  `json:"error,omitempty"`
}

type DataError struct {
	Code      string `json:"code"`
	Message   string `json:"message"`
	Retryable bool   `json:"retryable"`
}

func dataError(request DataRequest, code, message string, retryable bool) DataResponse {
	return DataResponse{Version: 1, RequestID: request.RequestID, OK: false,
		Error: &DataError{Code: code, Message: message, Retryable: retryable}}
}

// snapshotResult marshals a state section while still holding s.mu so the
// encoder never iterates maps or slices that settle/rollDay/sample/weather
// writes mutate under the same lock, then unmarshals into a private copy so
// callers marshal the response after the lock without touching shared state.
// The wire format is unchanged: Result is still map[string]interface{}{key:
// value} exactly like the former shallow-copy snapshot responses.
func snapshotResult[T any](s *Service, request DataRequest, key string, read func() T) DataResponse {
	s.mu.Lock()
	raw, err := json.Marshal(read())
	s.mu.Unlock()
	if err != nil {
		return dataError(request, "marshal-failed", err.Error(), false)
	}
	var value T
	if err = json.Unmarshal(raw, &value); err != nil {
		return dataError(request, "marshal-failed", err.Error(), false)
	}
	return DataResponse{Version: 1, RequestID: request.RequestID, OK: true,
		Result: map[string]interface{}{key: value}}
}

func (s *Service) handleRequest(request DataRequest) DataResponse {
	if request.Version != 0 && request.Version != 1 {
		return dataError(request, "unsupported-version", "不支持的协议版本", false)
	}
	switch request.Operation {
	case "metrics.snapshot":
		return snapshotResult(s, request, "metrics", func() Metrics {
			return s.state.Metrics
		})
	case "activity.snapshot":
		return snapshotResult(s, request, "activity", func() Activity {
			return s.state.Activity
		})
	case "desktop.snapshot":
		return snapshotResult(s, request, "desktop", func() Desktop {
			return s.state.Desktop
		})
	case "desktop.refresh":
		if s.refreshDesktop() {
			s.persist()
			s.publishDesktop()
		}
		return DataResponse{Version: 1, RequestID: request.RequestID, OK: true,
			Result: map[string]interface{}{"refreshed": true}}
	case "desktop.outputs":
		return s.configureDesktopOutputs(request)
	case "desktop.place":
		return s.placeDesktopEntries(request)
	case "weather.snapshot":
		return snapshotResult(s, request, "weather", func() WeatherState {
			return s.state.Weather
		})
	case "weather.search":
		query, _ := request.Payload["query"].(string)
		language, _ := request.Payload["language"].(string)
		limit := 8
		if value, ok := request.Payload["limit"].(float64); ok {
			limit = int(value)
		}
		locations, err := s.searchWeather(query, language, limit)
		if err != nil {
			return dataError(request, "weather-search-failed", weatherErrorMessage(err), true)
		}
		return DataResponse{Version: 1, RequestID: request.RequestID, OK: true,
			Result: map[string]interface{}{"locations": locations}}
	case "weather.refresh":
		accepted := s.startWeatherRefresh(true)
		return DataResponse{Version: 1, RequestID: request.RequestID, OK: true,
			Result: map[string]interface{}{"accepted": accepted}}
	case "weather.set-location":
		raw, err := json.Marshal(request.Payload["location"])
		if err != nil {
			return dataError(request, "invalid-location", "天气位置格式无效", false)
		}
		var location WeatherLocation
		if err = json.Unmarshal(raw, &location); err != nil {
			return dataError(request, "invalid-location", "天气位置格式无效", false)
		}
		if err = s.setWeatherLocation(location); err != nil {
			return dataError(request, "invalid-location", weatherErrorMessage(err), false)
		}
		return DataResponse{Version: 1, RequestID: request.RequestID, OK: true}
	case "weather.remove-location":
		id, _ := request.Payload["id"].(string)
		if err := s.removeWeatherLocation(id); err != nil {
			return dataError(request, "invalid-location", weatherErrorMessage(err), false)
		}
		return DataResponse{Version: 1, RequestID: request.RequestID, OK: true}
	case "weather.set-units":
		units, _ := request.Payload["units"].(string)
		if err := s.setWeatherUnits(units); err != nil {
			return dataError(request, "invalid-units", weatherErrorMessage(err), false)
		}
		return DataResponse{Version: 1, RequestID: request.RequestID, OK: true}
	case "activity.active-app":
		appID, _ := request.Payload["appID"].(string)
		name, _ := request.Payload["name"].(string)
		icon, _ := request.Payload["icon"].(string)
		s.mu.Lock()
		s.settle(time.Now())
		s.state.Activity.ActiveApp = appID
		s.state.Activity.Active = appID != ""
		if appID != "" {
			app := s.state.Activity.TodayApps[appID]
			app.Name = name
			if icon != "" {
				app.Icon = icon
			}
			s.state.Activity.TodayApps[appID] = app
		}
		s.mu.Unlock()
		return DataResponse{Version: 1, RequestID: request.RequestID, OK: true}
	default:
		return dataError(request, "unknown-operation", "未知的数据操作", false)
	}
}

func serve(s *Service, path string) error {
	_ = os.Remove(path)
	l, err := net.Listen("unix", path)
	if err != nil {
		return err
	}
	_ = os.Chmod(path, 0600)
	defer l.Close()
	for {
		c, e := l.Accept()
		if e != nil {
			return e
		}
		go func() {
			conn := &subscriberConn{Conn: c}
			defer conn.Close()
			s.subscribeDesktop(conn)
			defer s.unsubscribeDesktop(conn)
			scanner := bufio.NewScanner(conn)
			for scanner.Scan() {
				var request DataRequest
				if json.Unmarshal(scanner.Bytes(), &request) != nil {
					response := dataError(request, "invalid-json", "请求不是有效 JSON", false)
					raw, _ := json.Marshal(response)
					_ = conn.writeLine(append(raw, '\n'), 2*time.Second)
					continue
				}
				response := s.handleRequest(request)
				raw, _ := json.Marshal(response)
				// writeLine arms a fresh 2s deadline for every response and
				// clears it under the conn's write mutex, so broadcasts can
				// neither interleave bytes nor leave a stale absolute
				// deadline behind on this shared connection.
				_ = conn.writeLine(append(raw, '\n'), 2*time.Second)
			}
		}()
	}
}
