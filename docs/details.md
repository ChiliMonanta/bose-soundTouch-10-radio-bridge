# Bose Cloud Bridge Detailed Flow

This document describes the detailed HTTP call order used by the speaker and the
request/response format for each relevant endpoint.

## 1. Scope

- Bridge implementation: `cmd/bose-cloud-bridge/main.go`
- Goal: explain call sequence and payload formats without relying on the diagram
- Variables used in examples:
  - `SPEAKER_IP`: speaker IP on LAN
  - `BRIDGE_HOSTPORT`: bridge host and port, example `192.168.1.162:8080`

## 2. Startup And Provisioning Flow

Typical call sequence after speaker boot or reprovisioning:

1. `POST /marge/streaming/support/power_on`
2. `GET /marge/streaming/account/{accountId}/full`
3. `GET /marge/streaming/account/{accountId}/provider_settings`
4. `GET /marge/streaming/sourceproviders`
5. `GET /marge/streaming/account/{accountId}/sources`
6. `GET /bmx/registry/v1/services`
7. Optional in some flows: `GET /marge/streaming/device/{deviceId}/streaming_token`

Expected outcome:

- Speaker receives provider and source metadata
- `LOCAL_INTERNET_RADIO` becomes available in `/sources`

## 3. Preset Playback Flow

Typical sequence when a preset button is pressed:

1. Speaker resolves preset `location` into an Orion request payload
2. Speaker calls Orion endpoint, usually path style:
   - `GET /core02/svc-bmx-adapter-orion/prod/orion/{base64url-json}`
3. Bridge returns BMX playback JSON containing `audio.streamUrl`
4. Speaker fetches audio stream directly from radio provider URL

Important:

- Audio does not pass through this bridge
- Bridge only provides metadata and stream URL

## 4. Endpoint Request Formats

### 4.1 Power On

- Method: `POST`
- Path: `/marge/streaming/support/power_on`
- Body: none required
- Response: `200` with `{}`
- Response content type: `application/json`

Compatibility alias:

- `/streaming/support/power_on`

### 4.2 Account Full

- Method: `GET`
- Path: `/marge/streaming/account/{accountId}/full`
- Body: none
- Response: Bose XML account payload
- Response content type: `application/vnd.bose.streaming-v1.2+xml`

Compatibility alias:

- `/streaming/account/{accountId}/full`

### 4.3 Provider Settings

- Method: `GET`
- Path: `/marge/streaming/account/{accountId}/provider_settings`
- Body: none
- Response: Bose XML provider settings
- Response content type: `application/vnd.bose.streaming-v1.2+xml`

Compatibility alias:

- `/streaming/account/{accountId}/provider_settings`

### 4.4 Source Providers

- Method: `GET`
- Path: `/marge/streaming/sourceproviders`
- Body: none
- Response: Bose XML source provider list
- Response content type: `application/vnd.bose.streaming-v1.2+xml`

Compatibility alias:

- `/streaming/sourceproviders`

### 4.5 Account Sources

- Method: `GET`
- Path: `/marge/streaming/account/{accountId}/sources`
- Body: none
- Response: Bose XML source list including `LOCAL_INTERNET_RADIO`
- Response content type: `application/vnd.bose.streaming-v1.2+xml`

Compatibility alias:

- `/streaming/account/{accountId}/sources`

### 4.6 Streaming Token

- Method: `GET`
- Path: `/marge/streaming/device/{deviceId}/streaming_token`
- Body: none
- Response: status `200`, no body required
- Response headers include:
  - `Authorization`
  - `ETag`

Compatibility alias:

- `/streaming/device/{deviceId}/streaming_token`

### 4.7 BMX Registry

- Method: `GET`
- Path: `/bmx/registry/v1/services`
- Body: none
- Response: BMX services JSON with `LOCAL_INTERNET_RADIO`
- Response content type: `application/json`

Compatibility alias:

- `/registry/v1/services`

Notes:

- Bridge builds service URLs from request host and scheme
- `X-Forwarded-Proto` is respected

### 4.8 Orion Station Resolve

- Method: `GET`
- Primary path: `/orion/station?data={base64url-json}`
- Common speaker path: `/core02/svc-bmx-adapter-orion/prod/orion/{base64url-json}`
- Body: none
- Response: BMX playback JSON
- Response content type: `application/json`

Accepted path aliases:

- `/orion/{base64url-json}`
- `/svc-bmx-adapter-orion/prod/orion/{base64url-json}`
- `/core02/svc-bmx-adapter-orion/prod/orion/{base64url-json}`

If `data` is missing or invalid:

- Status `400`

## 5. Orion Payload Format

The payload is base64url encoded JSON.

Decoded schema:

```json
{
  "streamUrl": "https://example.com/live",
  "name": "Station Name",
  "imageUrl": "https://example.com/image.png"
}
```

Rules:

- `streamUrl` is required
- `name` defaults to `Internet Radio` if omitted
- `imageUrl` is optional

## 6. Orion Response Format

Example response shape:

```json
{
  "audio": {
    "hasPlaylist": true,
    "isRealtime": true,
    "maxTimeout": 60,
    "streamUrl": "https://example.com/live",
    "streams": [
      {
        "hasPlaylist": true,
        "isRealtime": true,
        "bufferingTimeout": 20,
        "connectingTimeout": 10,
        "maxTimeout": 60,
        "streamUrl": "https://example.com/live"
      }
    ]
  },
  "imageUrl": "",
  "isFavorite": false,
  "name": "Station Name",
  "streamType": "liveRadio"
}
```

## 7. Operational Endpoints

- `GET /healthz` returns `ok`
- `GET /` returns BMX registry response
- Unmatched routes return `200` catch-all (JSON `{}` for common methods)

## 8. Quick Verification Commands

```sh
# Verify provisioning state on speaker
curl http://$SPEAKER_IP:8090/info
curl http://$SPEAKER_IP:8090/sources

# Probe bridge registry
curl http://$BRIDGE_HOSTPORT/bmx/registry/v1/services

# Probe Orion with query mode
curl "http://$BRIDGE_HOSTPORT/orion/station?data=<base64url-json>"
```
