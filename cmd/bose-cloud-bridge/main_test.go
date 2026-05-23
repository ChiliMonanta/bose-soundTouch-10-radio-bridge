package main

import (
	"context"
	"encoding/base64"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/aws/aws-lambda-go/events"
)

func TestDecodeStationData_OK(t *testing.T) {
	raw := `{"name":"P4 Stockholm","streamUrl":"https://live1.sr.se/p4sth-aac-320"}`
	enc := base64.RawURLEncoding.EncodeToString([]byte(raw))

	got, err := decodeStationData(enc)
	if err != nil {
		t.Fatalf("decodeStationData returned error: %v", err)
	}
	if got.Name != "P4 Stockholm" {
		t.Fatalf("expected Name P4 Stockholm, got %q", got.Name)
	}
	if got.StreamURL != "https://live1.sr.se/p4sth-aac-320" {
		t.Fatalf("unexpected StreamURL: %q", got.StreamURL)
	}
}

func TestDecodeStationData_MissingNameDefaults(t *testing.T) {
	raw := `{"streamUrl":"https://example.com/live"}`
	enc := base64.RawURLEncoding.EncodeToString([]byte(raw))

	got, err := decodeStationData(enc)
	if err != nil {
		t.Fatalf("decodeStationData returned error: %v", err)
	}
	if got.Name != "Internet Radio" {
		t.Fatalf("expected default name, got %q", got.Name)
	}
}

func TestDecodeStationData_Invalid(t *testing.T) {
	_, err := decodeStationData("not-valid-base64")
	if err == nil {
		t.Fatal("expected error for invalid base64")
	}
}

func TestDecodeStationData_MissingStreamURL(t *testing.T) {
	raw := `{"name":"No URL"}`
	enc := base64.RawURLEncoding.EncodeToString([]byte(raw))

	_, err := decodeStationData(enc)
	if err == nil {
		t.Fatal("expected error for missing streamUrl")
	}
}

func TestBuildMux_BmxRegistryIncludesOrionPath(t *testing.T) {
	mux := buildMux()
	req := httptest.NewRequest(http.MethodGet, "/bmx/registry/v1/services", nil)
	req.Host = "example.com"
	req.Header.Set("X-Forwarded-Proto", "https")
	rr := httptest.NewRecorder()

	mux.ServeHTTP(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rr.Code)
	}
	body := rr.Body.String()
	if !strings.Contains(body, "https://example.com/orion/station") {
		t.Fatalf("unexpected response body: %s", body)
	}
}

func TestBuildMux_OrionStation_HappyPath(t *testing.T) {
	mux := buildMux()
	raw := `{"name":"P4 Stockholm","streamUrl":"https://live1.sr.se/p4sth-aac-320"}`
	enc := base64.RawURLEncoding.EncodeToString([]byte(raw))

	req := httptest.NewRequest(http.MethodGet, "/orion/station?data="+enc, nil)
	rr := httptest.NewRecorder()

	mux.ServeHTTP(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", rr.Code, rr.Body.String())
	}
	if !strings.Contains(rr.Body.String(), "p4sth-aac-320") {
		t.Fatalf("expected stream URL in response, got %s", rr.Body.String())
	}
}

func TestBuildMux_OrionStation_PathStyleAlias_HappyPath(t *testing.T) {
	mux := buildMux()
	raw := `{"name":"P1","streamUrl":"https://example.com/live.mp3"}`
	enc := base64.RawURLEncoding.EncodeToString([]byte(raw))

	req := httptest.NewRequest(http.MethodGet, "/core02/svc-bmx-adapter-orion/prod/orion/"+enc, nil)
	rr := httptest.NewRecorder()

	mux.ServeHTTP(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", rr.Code, rr.Body.String())
	}
	if !strings.Contains(rr.Body.String(), "live.mp3") {
		t.Fatalf("expected stream URL in response, got %s", rr.Body.String())
	}
}

func TestBuildMux_OrionStation_RejectsMissingData(t *testing.T) {
	mux := buildMux()
	req := httptest.NewRequest(http.MethodGet, "/orion/station", nil)
	rr := httptest.NewRecorder()

	mux.ServeHTTP(rr, req)

	if rr.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", rr.Code)
	}
}

func TestBuildMux_PowerOn_MethodNotAllowed(t *testing.T) {
	mux := buildMux()
	req := httptest.NewRequest(http.MethodGet, "/marge/streaming/support/power_on", nil)
	rr := httptest.NewRecorder()

	mux.ServeHTTP(rr, req)

	if rr.Code != http.StatusMethodNotAllowed {
		t.Fatalf("expected 405, got %d", rr.Code)
	}
}

func TestBuildMux_StreamingToken_OK(t *testing.T) {
	mux := buildMux()
	req := httptest.NewRequest(http.MethodGet, "/streaming/device/abc/streaming_token", nil)
	rr := httptest.NewRecorder()

	mux.ServeHTTP(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rr.Code)
	}
	if rr.Header().Get("Authorization") == "" {
		t.Fatal("expected Authorization header")
	}
}

func TestBuildMux_StreamingToken_NotFoundWhenSuffixMissing(t *testing.T) {
	mux := buildMux()
	req := httptest.NewRequest(http.MethodGet, "/streaming/device/abc/not_token", nil)
	rr := httptest.NewRecorder()

	mux.ServeHTTP(rr, req)

	if rr.Code != http.StatusNotFound {
		t.Fatalf("expected 404, got %d", rr.Code)
	}
}

func TestBuildMux_AccountFull_ParsesAccountID(t *testing.T) {
	mux := buildMux()
	req := httptest.NewRequest(http.MethodGet, "/marge/streaming/account/abc123/full", nil)
	rr := httptest.NewRecorder()

	mux.ServeHTTP(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rr.Code)
	}
	if !strings.Contains(rr.Body.String(), "abc123") {
		t.Fatalf("expected account id in body, got %s", rr.Body.String())
	}
}

func TestParseAccountID_EmptyReturnsUnknown(t *testing.T) {
	got := parseAccountID("/marge/streaming/account//full", "/full")
	if got != "unknown" {
		t.Fatalf("expected unknown, got %q", got)
	}
}

func TestRunningInLambda(t *testing.T) {
	t.Setenv("AWS_LAMBDA_RUNTIME_API", "127.0.0.1:9001")
	if !runningInLambda() {
		t.Fatal("expected runningInLambda to be true")
	}
}

func TestRequestFromLambdaEvent(t *testing.T) {
	event := events.APIGatewayV2HTTPRequest{
		RawPath:        "/orion/station",
		RawQueryString: "data=abc",
		Headers: map[string]string{
			"host":              "example.lambda-url.eu-north-1.on.aws",
			"x-forwarded-proto": "https",
		},
		RequestContext: events.APIGatewayV2HTTPRequestContext{
			DomainName: "example.lambda-url.eu-north-1.on.aws",
			HTTP: events.APIGatewayV2HTTPRequestContextHTTPDescription{
				Method:   http.MethodGet,
				SourceIP: "1.2.3.4",
			},
		},
	}

	req, err := requestFromLambdaEvent(context.Background(), event)
	if err != nil {
		t.Fatalf("requestFromLambdaEvent returned error: %v", err)
	}
	if req.Method != http.MethodGet {
		t.Fatalf("expected GET, got %s", req.Method)
	}
	if req.URL.Path != "/orion/station" {
		t.Fatalf("expected /orion/station, got %s", req.URL.Path)
	}
	if req.URL.RawQuery != "data=abc" {
		t.Fatalf("expected data=abc, got %s", req.URL.RawQuery)
	}
	if req.Host != "example.lambda-url.eu-north-1.on.aws" {
		t.Fatalf("unexpected host: %s", req.Host)
	}
	if req.Header.Get("X-Forwarded-Proto") != "https" {
		t.Fatalf("expected https proto header, got %s", req.Header.Get("X-Forwarded-Proto"))
	}
}

func TestLambdaAdapter_Handle(t *testing.T) {
	raw := `{"name":"P4 Stockholm","streamUrl":"https://live1.sr.se/p4sth-aac-320"}`
	enc := base64.RawURLEncoding.EncodeToString([]byte(raw))
	adapter := &lambdaAdapter{handler: requestLogger(buildMux())}

	event := events.APIGatewayV2HTTPRequest{
		RawPath:        "/orion/station",
		RawQueryString: "data=" + enc,
		Headers: map[string]string{
			"host":              "example.lambda-url.eu-north-1.on.aws",
			"x-forwarded-proto": "https",
		},
		RequestContext: events.APIGatewayV2HTTPRequestContext{
			HTTP: events.APIGatewayV2HTTPRequestContextHTTPDescription{
				Method: http.MethodGet,
			},
		},
	}

	resp, err := adapter.Handle(context.Background(), event)
	if err != nil {
		t.Fatalf("Handle returned error: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", resp.StatusCode, resp.Body)
	}
	if !strings.Contains(resp.Body, "p4sth-aac-320") {
		t.Fatalf("expected stream URL in response, got %s", resp.Body)
	}
}
