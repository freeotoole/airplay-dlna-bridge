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
echo "[bridge] Ensuring a default sink exists (load null sink if needed)"
# Create a null sink so shairport-sync has a default sink when no ALSA devices present
if ! pactl list short sinks | grep -q .; then
  echo "[bridge] No sinks found, attempting to load null sink 'airplay_null'"
  for attempt in 1 2 3 4 5; do
    module_index=$(pactl load-module module-null-sink sink_name=airplay_null sink_properties=device.description="AirPlay Null Sink" 2>&1 || true)
    if echo "$module_index" | grep -q '^[0-9]\+'; then
      echo "[bridge] Loaded null sink (module index: ${module_index})"
      pactl set-default-sink airplay_null || true
      break
    else
      echo "[bridge] Failed to load null sink (attempt ${attempt}/5): ${module_index}"
      sleep 1
    fi
  done
fi

echo "[bridge] Current sinks:"
pactl list short sinks || true

# Wait for at least one sink to exist before starting pulseaudio-dlna
wait_seconds=0
max_wait=15
while ! pactl list short sinks | grep -q .; do
  if [ $wait_seconds -ge $max_wait ]; then
    echo "[bridge] No sinks after ${max_wait}s — will still start pulseaudio-dlna but it may ignore PulseAudio until sinks appear"
    break
  fi
  echo "[bridge] Waiting for sinks to appear... (${wait_seconds}/${max_wait})"
  sleep 1
  wait_seconds=$((wait_seconds+1))

done

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

# Give pulseaudio-dlna a few seconds to detect sinks
sleep 2

# If pulseaudio-dlna started with no sinks, try restarting it once more after sinks appear
if ! pactl list short sinks | grep -q .; then
  echo "[bridge] pulseaudio-dlna started but still no sinks; attempting to load null sink and restart pulseaudio-dlna"
  pactl load-module module-null-sink sink_name=airplay_null sink_properties=device.description="AirPlay Null Sink" || true
  pactl set-default-sink airplay_null || true
  sleep 1
  pkill -f pulseaudio-dlna || true
  pulseaudio-dlna "${DLNA_ARGS[@]}" &
  DLNA_PID=$!
fi
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
