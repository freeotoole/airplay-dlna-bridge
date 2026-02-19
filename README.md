# AirPlay → DLNA Bridge (Unraid / Docker)

Receive AirPlay audio from Apple devices and forward it to a DLNA/UPnP renderer (e.g., WiiM Ultra).

## How it works

Apple AirPlay → shairport-sync → PulseAudio → pulseaudio-dlna → DLNA Renderer (WiiM)

## Requirements

- Docker container must run with **host networking** (AirPlay uses mDNS/Bonjour)
- Works best when Unraid is wired and renderer is on strong 5GHz WiFi (or wired)

## Quick Start (Unraid)

- Network Type: **Host**
- Privileged: **Yes**
- Add ENV:
  - `AIRPLAY_NAME` (what shows up on iPhone/Mac)
  - `DLNA_ENCODER` (`wav` for uncompressed, `flac` for lossless + more robust)
  - `DLNA_RENDERER` (optional substring filter, e.g. `WiiM`)

## Recommended settings

- If you get dropouts on WiFi, switch:
  - `DLNA_ENCODER=flac` (still lossless, much lower bandwidth)

## Environment variables

| Var              |               Default | Notes                                 |
| ---------------- | --------------------: | ------------------------------------- |
| AIRPLAY_NAME     |        Unraid AirPlay | AirPlay target name                   |
| AIRPLAY_PASSWORD |               (blank) | Optional                              |
| DLNA_STREAM_NAME | Unraid AirPlay → DLNA | DLNA stream name                      |
| DLNA_ENCODER     |                   wav | wav (uncompressed) or flac (lossless) |
| DLNA_RENDERER    |               (blank) | Optional renderer substring filter    |
| DLNA_TTL         |                    60 | Renderer re-discovery TTL             |

## Notes

- This is intended for music listening. Expect latency (AirPlay buffer + DLNA buffer).
