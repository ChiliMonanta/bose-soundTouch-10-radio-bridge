#!/bin/bash
set -euo pipefail

# tunein-preset-update.sh
# Resolve a TuneIn station to a playable stream URL and write it to presets config.
# Also appends a JSON log record so changes are traceable in git.
#
# Usage:
#   ./scripts/tunein-preset-update.sh --slot 1 --name "BBC Radio 1" --id s24939
#   ./scripts/tunein-preset-update.sh --slot 2 --name "P4 Stockholm" --query "P4 Stockholm"
#   ./scripts/tunein-preset-update.sh --query "P4 Stockholm" --test-play
#   ./scripts/tunein-preset-update.sh --query "P4 Stockholm" --dry-run
#   ./scripts/tunein-preset-update.sh --query "P4 Stockholm" --play-on-bose 192.168.1.142
#
# Optional:
#   --config config/presets.json
#   --log logs/preset-updates.jsonl
#   --test-play
#   --dry-run
#   --play-on-bose <speaker_ip>
#   --player auto|ffplay|vlc|open

CONFIG_FILE="config/presets.json"
LOG_FILE="logs/preset-updates.jsonl"
SLOT=""
PRESET_NAME=""
TUNEIN_ID=""
QUERY=""
TEST_PLAY=0
DRY_RUN=0
PLAY_ON_BOSE_IP=""
PLAYER="auto"

# Keep network calls bounded so the script does not appear to hang on slow endpoints.
CURL_ARGS=(--connect-timeout 8 --max-time 20)

strip_trailing_cr() {
  local v="$1"
  printf "%s" "${v%$'\r'}"
}

usage() {
  cat <<EOF
Usage:
  $0 --slot <1-6> --name <preset_name> (--id <tunein_station_id> | --query <station_name>) [--config <file>] [--log <file>]
  $0 (--id <tunein_station_id> | --query <station_name>) --test-play [--player auto|ffplay|vlc|open]
  $0 (--id <tunein_station_id> | --query <station_name>) --dry-run
  $0 (--id <tunein_station_id> | --query <station_name>) --play-on-bose <speaker_ip>

Examples:
  $0 --slot 1 --name "BBC Radio 1" --id s24939
  $0 --slot 2 --name "P4 Stockholm" --query "P4 Stockholm"
  $0 --query "P4 Stockholm" --test-play
  $0 --query "P4 Stockholm" --dry-run
  $0 --query "P4 Stockholm" --play-on-bose 192.168.1.142
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --slot)
      SLOT="${2:-}"
      shift 2
      ;;
    --name)
      PRESET_NAME="${2:-}"
      shift 2
      ;;
    --id)
      TUNEIN_ID="${2:-}"
      shift 2
      ;;
    --query)
      QUERY="${2:-}"
      shift 2
      ;;
    --config)
      CONFIG_FILE="${2:-}"
      shift 2
      ;;
    --log)
      LOG_FILE="${2:-}"
      shift 2
      ;;
    --test-play)
      TEST_PLAY=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --play-on-bose)
      PLAY_ON_BOSE_IP="${2:-}"
      shift 2
      ;;
    --player)
      PLAYER="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ "$DRY_RUN" -eq 1 && "$TEST_PLAY" -eq 1 ]]; then
  echo "Error: --dry-run and --test-play cannot be combined" >&2
  exit 1
fi

if [[ "$DRY_RUN" -eq 1 && -n "$PLAY_ON_BOSE_IP" ]]; then
  echo "Error: --dry-run and --play-on-bose cannot be combined" >&2
  exit 1
fi

if [[ "$PLAYER" != "auto" && "$PLAYER" != "ffplay" && "$PLAYER" != "vlc" && "$PLAYER" != "open" ]]; then
  echo "Error: --player must be one of: auto, ffplay, vlc, open" >&2
  exit 1
fi

if [[ "$TEST_PLAY" -eq 0 && "$DRY_RUN" -eq 0 && -z "$PLAY_ON_BOSE_IP" ]]; then
  if [[ -z "$SLOT" || -z "$PRESET_NAME" ]]; then
    echo "Error: --slot and --name are required unless --test-play or --play-on-bose is used" >&2
    usage
    exit 1
  fi
fi

if [[ -n "$TUNEIN_ID" && -n "$QUERY" ]]; then
  echo "Error: use either --id or --query, not both" >&2
  exit 1
fi

if [[ -z "$TUNEIN_ID" && -z "$QUERY" ]]; then
  echo "Error: either --id or --query is required" >&2
  exit 1
fi

if [[ "$TEST_PLAY" -eq 0 && "$DRY_RUN" -eq 0 && -z "$PLAY_ON_BOSE_IP" ]]; then
  if ! [[ "$SLOT" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: --slot must be a positive integer" >&2
    exit 1
  fi
fi

if [[ "$TEST_PLAY" -eq 0 && "$DRY_RUN" -eq 0 && -z "$PLAY_ON_BOSE_IP" ]]; then
  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: config file not found: $CONFIG_FILE" >&2
    exit 1
  fi
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required" >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "Error: curl is required" >&2
  exit 1
fi

mkdir -p "$(dirname "$LOG_FILE")"

play_stream() {
  local url="$1"
  local player="$2"

  if [[ "$player" == "auto" ]]; then
    if command -v ffplay >/dev/null 2>&1; then
      player="ffplay"
    elif command -v vlc >/dev/null 2>&1; then
      player="vlc"
    elif command -v open >/dev/null 2>&1; then
      player="open"
    else
      echo "No local player found (ffplay/vlc/open). URL only:" >&2
      echo "$url"
      return 0
    fi
  fi

  case "$player" in
    ffplay)
      echo "Launching ffplay..."
      ffplay -nodisp "$url"
      ;;
    vlc)
      echo "Launching VLC..."
      vlc "$url"
      ;;
    open)
      echo "Opening URL with default macOS app..."
      open "$url"
      ;;
  esac
}

xml_escape() {
  printf "%s" "$1" \
    | sed -e 's/&/\&amp;/g' \
          -e 's/</\&lt;/g' \
          -e 's/>/\&gt;/g' \
          -e 's/"/\&quot;/g' \
          -e "s/'/\&apos;/g"
}

play_on_bose() {
  local ip="$1"
  local stream_url="$2"
  local item_name="$3"

  local esc_url esc_name payload
  esc_url="$(xml_escape "$stream_url")"
  esc_name="$(xml_escape "$item_name")"
  payload="<ContentItem source=\"LOCAL_INTERNET_RADIO\" type=\"stationurl\" location=\"$esc_url\"><itemName>$esc_name</itemName></ContentItem>"

  curl -fsS -X POST "http://$ip:8090/select" \
    -H "Content-Type: application/xml" \
    -d "$payload" >/dev/null

  echo "Started playback on Bose speaker at $ip"
  echo "Tip: verify with curl http://$ip:8090/now_playing"
}

extract_urls_from_tune_xml() {
  sed -n 's/.*URL="\([^"]*\)".*/\1/p'
}

extract_candidate_urls() {
  local raw="$1"

  if echo "$raw" | grep -q 'URL="'; then
    echo "$raw" | extract_urls_from_tune_xml
    return 0
  fi

  # Some TuneIn responses are plain newline-separated URLs.
  echo "$raw" | grep -E '^https?://' || true
}

resolve_playlist() {
  local url="$1"
  local body
  body="$(curl -fsSL "${CURL_ARGS[@]}" "$url" || true)"

  if [[ -z "$body" ]]; then
    return 0
  fi

  # PLS: File1=http://...
  if echo "$body" | grep -qi '^\[playlist\]'; then
    echo "$body" | sed -n 's/^File[0-9][0-9]*=//p'
    return 0
  fi

  # M3U/M3U8: lines that are not comments
  if echo "$body" | grep -qi '^#EXTM3U'; then
    echo "$body" | grep -Evi '^\s*#' | sed '/^\s*$/d'
    return 0
  fi

  # ASX-like XML: href="..."
  if echo "$body" | grep -qi '<asx\|<entry\|<ref'; then
    echo "$body" | sed -n 's/.*href="\([^"]*\)".*/\1/pI'
    return 0
  fi

  # Unknown payload: fallback to original URL.
  echo "$url"
}

get_station_id_from_query() {
  local q="$1"
  local enc
  enc="$(jq -nr --arg v "$q" '$v|@uri')"

  local xml
  xml="$(curl -fsSL "${CURL_ARGS[@]}" "https://opml.radiotime.com/Search.ashx?query=$enc")"

  # Prefer guide_id=sNNNN, fallback to id=sNNNN.
  local id
  id="$(echo "$xml" | sed -n 's/.*guide_id="\(s[0-9][0-9]*\)".*/\1/p' | head -n1)"
  if [[ -z "$id" ]]; then
    id="$(echo "$xml" | sed -n 's/.*id="\(s[0-9][0-9]*\)".*/\1/p' | head -n1)"
  fi
  echo "$id"
}

if [[ -n "$QUERY" ]]; then
  TUNEIN_ID="$(get_station_id_from_query "$QUERY")"
  if [[ -z "$TUNEIN_ID" ]]; then
    echo "Error: no TuneIn station id found for query: $QUERY" >&2
    exit 2
  fi
fi

TUNE_XML_URL="https://opml.radiotime.com/Tune.ashx?id=$TUNEIN_ID&formats=mp3,aac,ogg,hls"
RAW_TUNE_XML="$(curl -fsSL "${CURL_ARGS[@]}" "$TUNE_XML_URL")"
CANDIDATE_URLS="$(extract_candidate_urls "$RAW_TUNE_XML" | sed '/^\s*$/d' || true)"

if [[ -z "$CANDIDATE_URLS" ]]; then
  echo "Error: no candidate URLs found from TuneIn id: $TUNEIN_ID" >&2
  exit 3
fi

STREAM_URL=""
while IFS= read -r candidate; do
  [[ -z "$candidate" ]] && continue
  candidate="$(strip_trailing_cr "$candidate")"
  resolved="$(resolve_playlist "$candidate" || true)"
  if [[ -n "$resolved" ]]; then
    STREAM_URL="$(echo "$resolved" | sed 's/\r$//' | grep -E '^https?://' | head -n1 || true)"
    [[ -n "$STREAM_URL" ]] && break
  fi
done <<< "$CANDIDATE_URLS"

if [[ -z "$STREAM_URL" ]]; then
  # Fallback to first candidate if resolution failed.
  STREAM_URL="$(echo "$CANDIDATE_URLS" | sed 's/\r$//' | grep -E '^https?://' | head -n1 || true)"
fi

STREAM_URL="$(strip_trailing_cr "$STREAM_URL")"

if [[ -z "$STREAM_URL" ]]; then
  echo "Error: could not resolve a usable stream URL" >&2
  exit 4
fi

ORIGINAL_STREAM_URL="$STREAM_URL"
NORMALIZED_STREAM_URL="${ORIGINAL_STREAM_URL%%\?*}"
NORMALIZED_APPLIED=0
if [[ "$NORMALIZED_STREAM_URL" != "$ORIGINAL_STREAM_URL" ]]; then
  NORMALIZED_APPLIED=1
  STREAM_URL="$NORMALIZED_STREAM_URL"
fi

echo "Resolved stream URL: $STREAM_URL"
if [[ "$NORMALIZED_APPLIED" -eq 1 ]]; then
  echo "Normalization: stripped query parameters"
  echo "Original resolved URL: $ORIGINAL_STREAM_URL"
  echo "Normalized stream URL: $STREAM_URL"
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "Dry-run mode: no playback, preset config, or log files were changed."
  exit 0
fi

PLAY_NAME="$PRESET_NAME"
if [[ -z "$PLAY_NAME" ]]; then
  if [[ -n "$QUERY" ]]; then
    PLAY_NAME="$QUERY"
  elif [[ -n "$TUNEIN_ID" ]]; then
    PLAY_NAME="$TUNEIN_ID"
  else
    PLAY_NAME="TuneIn Stream"
  fi
fi

if [[ -n "$PLAY_ON_BOSE_IP" ]]; then
  play_on_bose "$PLAY_ON_BOSE_IP" "$STREAM_URL" "$PLAY_NAME"
  echo "Play-on-Bose mode: no preset config or log files were changed."
  exit 0
fi

if [[ "$TEST_PLAY" -eq 1 ]]; then
  play_stream "$STREAM_URL" "$PLAYER"
  echo "Test-play mode: no preset config or log files were changed."
  exit 0
fi

TMP_FILE="$(mktemp)"

jq \
  --argjson slot "$SLOT" \
  --arg name "$PRESET_NAME" \
  --arg stream "$STREAM_URL" \
  '
  if any(.channels[]; .slot == $slot) then
    .channels = (.channels | map(if .slot == $slot then .name = $name | .streamUrl = $stream else . end))
  else
    .channels += [{"slot": $slot, "name": $name, "streamUrl": $stream}]
  end
  | .channels |= sort_by(.slot)
  ' "$CONFIG_FILE" > "$TMP_FILE"

mv "$TMP_FILE" "$CONFIG_FILE"

TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
LOG_ENTRY="$(jq -nc \
  --arg ts "$TIMESTAMP" \
  --arg config "$CONFIG_FILE" \
  --arg name "$PRESET_NAME" \
  --arg id "$TUNEIN_ID" \
  --arg query "$QUERY" \
  --arg stream "$STREAM_URL" \
  --arg original_stream "$ORIGINAL_STREAM_URL" \
  --arg normalized_stream "$NORMALIZED_STREAM_URL" \
  --arg tune_xml "$TUNE_XML_URL" \
  --argjson slot "$SLOT" \
  --argjson normalized_applied "$NORMALIZED_APPLIED" \
  '{timestamp:$ts,slot:$slot,name:$name,tuneinId:$id,query:$query,streamUrl:$stream,originalStreamUrl:$original_stream,normalizedStreamUrl:$normalized_stream,streamUrlNormalized:$normalized_applied,tuneXmlUrl:$tune_xml,config:$config}')"

echo "$LOG_ENTRY" >> "$LOG_FILE"

echo "Updated preset slot $SLOT in $CONFIG_FILE"
echo "Name: $PRESET_NAME"
echo "TuneIn ID: $TUNEIN_ID"
echo "Stream URL: $STREAM_URL"
echo "Log entry appended to: $LOG_FILE"
