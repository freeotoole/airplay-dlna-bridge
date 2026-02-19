#!/usr/bin/env bash
set -euo pipefail

# ----------------------------
# Config via ENV (community-friendly)
# ----------------------------
AIRPLAY_NAME="${AIRPLAY_NAME:-Unraid AirPlay}"
AIRPLAY_PASSWORD="${AIRPLAY_PASSWORD:-}"   # optional
AIRPLAY_LATENCY_MS="${AIRPLAY_LATENCY_MS:-0}"  # optional, shairport can add latency

DLNA_STREAM_NAME="${DLNA_STREAM_NAME:-Unraid AirPlay → DLNA}"
DLNA_ENCODER="${DLNA_ENCODER:-wav}"        # wav | flac | mp3 (lossless: wav/flac)
DLNA_TTL="${DLNA_TTL:-60}"
DLNA_RENDERER="${DLNA_RENDERER:-}"         # optional: match a specific renderer by substring
DLNA_BIND="${DLNA_BIND:-0.0.0.0}"          # HTTP bind
PULSE_SAMPLERATE="${PULSE_SAMPLERATE:-44100}"
PULSE_FORMAT="${PULSE_FORMAT:-s16le}"      # s16le is safest
LOG_LEVEL="${LOG_LEVEL:-info}"             # shairport: info|debug|trace

# ----------------------------
# Start dbus + avahi (mDNS)
# ----------------------------
mkdir -p /run/dbus
dbus-daemon --system --fork

# Avahi inside docker wants host networking to be reliable.
avahi-daemon --daemonize --no-chroot

# ----------------------------
# Setup PulseAudio runtime directory
# ----------------------------
mkdir -p /run/pulse
chmod 755 /run/pulse
export PULSE_RUNTIME_PATH=/run/pulse

# Ensure clients use the system-mode socket
export PULSE_SERVER=/run/pulse/native

# Create pulseaudio config for system mode
cat > /etc/pulse/system.pa <<'EOF'
load-module module-native-protocol-unix auth-anonymous=1 socket=/run/pulse/native
load-module module-alsa-sink
load-module module-alsa-source
load-module module-dbus-protocol
EOF

# ----------------------------
# Start PulseAudio (system mode)
# ----------------------------
echo "[bridge] Starting PulseAudio in system mode..."
pulseaudio --system \
  --disallow-exit \
  --exit-idle-time=-1 \
  --log-target=stderr \
  --daemonize=yes

# Wait and verify PulseAudio is ready with more verbose checking
echo "[bridge] Waiting for PulseAudio to initialize..."
for i in {1..30}; do
  if [ -S /run/pulse/native ] && pactl info >/dev/null 2>&1; then
    echo "[bridge] PulseAudio is ready"
    break
  fi
  if [ $i -eq 30 ]; then
    echo "[bridge] PulseAudio failed to initialize after 30 seconds"
    pulseaudio --check -v
    exit 1
  fi
  sleep 1
done

# ----------------------------
# Start pulseaudio-dlna
# ----------------------------
DLNA_ARGS=(
  --encoder "${DLNA_ENCODER}"
  --ssdp-ttl "${DLNA_TTL}"
  --host "${DLNA_BIND}"
)

# Renderer pinning (if explicit URLs provided)
# Usage: pass space-separated URLs in DLNA_RENDERER
if [[ -n "${DLNA_RENDERER}" ]]; then
  DLNA_ARGS+=( --renderer-urls "${DLNA_RENDERER}" )
fi

echo "[bridge] Starting pulseaudio-dlna: encoder=${DLNA_ENCODER}, renderers='${DLNA_RENDERER}'"
pulseaudio-dlna "${DLNA_ARGS[@]}" &
DLNA_PID=$!

# Wait a moment for sinks to appear
sleep 2

# ----------------------------
# Generate shairport-sync config
# ----------------------------
# Convert latency from ms to seconds for config file
AIRPLAY_LATENCY_SECONDS=$(echo "scale=6; ${AIRPLAY_LATENCY_MS} / 1000" | bc)

export AIRPLAY_NAME AIRPLAY_PASSWORD AIRPLAY_LATENCY_SECONDS LOG_LEVEL
envsubst < /shairport-sync.conf.tmpl > /tmp/shairport-sync.conf

echo "[bridge] Starting shairport-sync: name='${AIRPLAY_NAME}'"

# Add retry logic with exec on final attempt
for attempt in {1..5}; do
  if [ $attempt -lt 5 ]; then
    shairport-sync -c /tmp/shairport-sync.conf && break
    echo "[bridge] shairport-sync connection failed (attempt $attempt/5), retrying in 3 seconds..."
    sleep 3
  else
    exec shairport-sync -c /tmp/shairport-sync.conf
  fi
done
