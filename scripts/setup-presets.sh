#!/bin/bash
set -e

# setup-presets.sh
# Configure radio presets on Bose SoundTouch speaker via /storePreset
# Usage: ./scripts/setup-presets.sh <speaker_ip> [config_file]

SPEAKER_IP="${1}"
CONFIG_FILE="${2:-config/presets.json}"
TIMEOUT=5

if [ -z "$SPEAKER_IP" ]; then
  echo "Usage: $0 <speaker_ip> [config_file]"
  echo ""
  echo "Example:"
  echo "  $0 192.168.1.142"
  echo "  $0 192.168.1.142 config/presets.json"
  exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Config file not found: $CONFIG_FILE"
  exit 1
fi

# Check if speaker is reachable
if ! nc -z -w2 "$SPEAKER_IP" 8090 2>/dev/null; then
  echo "Error: Cannot reach speaker at $SPEAKER_IP:8090"
  echo "Make sure:"
  echo "  1. Speaker is powered on"
  echo "  2. Connected to same network"
  echo "  3. IP address is correct"
  exit 1
fi

echo "Setting up presets on $SPEAKER_IP..."
echo ""

xml_escape() {
  printf '%s' "$1" \
    | sed -e 's/&/\&amp;/g' \
          -e 's/</\&lt;/g' \
          -e 's/>/\&gt;/g' \
          -e 's/"/\&quot;/g' \
          -e "s/'/\&apos;/g"
}

base64url_encode() {
  printf '%s' "$1" | base64 | tr -d '\n=' | tr '+/' '-_'
}

# Extract channels from JSON and write presets directly.
jq -r '.channels[] | 
  "SLOT=\(.slot)\nNAME=\(.name)\nURL=\(.streamUrl)"' "$CONFIG_FILE" | 
while IFS='=' read -r key val; do
  case "$key" in
    SLOT)
      SLOT="$val"
      ;;
    NAME)
      NAME="$val"
      ;;
    URL)
      STREAM_URL=$(printf '%s' "$val" | tr -d '\r')
      LOCATION_JSON=$(printf '{"streamUrl":"%s","imageUrl":"","name":"%s"}' "$STREAM_URL" "$NAME")
      LOCATION=$(base64url_encode "$LOCATION_JSON")
      ESCAPED_LOCATION=$(xml_escape "$LOCATION")
      ESCAPED_NAME=$(xml_escape "$NAME")
      PRESET_BODY="<preset id=\"${SLOT}\"><ContentItem source=\"LOCAL_INTERNET_RADIO\" sourceAccount=\"\" type=\"stationurl\" location=\"${ESCAPED_LOCATION}\" isPresetable=\"true\"><itemName>${ESCAPED_NAME}</itemName></ContentItem></preset>"

      echo -n "Slot $SLOT ($NAME)... "

      if curl -s -X POST "http://$SPEAKER_IP:8090/storePreset" \
        -H 'Content-Type: application/xml' \
        --max-time "$TIMEOUT" \
           -d "$PRESET_BODY" >/dev/null 2>&1; then
        echo "✓"
      else
        echo "✗ (failed)"
      fi
      ;;
  esac
done

echo ""
echo "Setup complete!"
echo ""
echo "Next steps:"
echo "  1. Press preset buttons 1-6 on speaker or app to test"
echo "  2. To verify presets were saved:"
echo "     curl http://$SPEAKER_IP:8090/presets"
echo ""
