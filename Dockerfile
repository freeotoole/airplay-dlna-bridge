FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
  apt-get install -y --no-install-recommends \
  dbus avahi-daemon \
  pulseaudio pulseaudio-utils \
  shairport-sync \
  pulseaudio-dlna \
  curl jq gettext bc \
  && apt-get clean && \
  rm -rf /var/lib/apt/lists/* && \
  mkdir -p /run/pulse && \
  chmod 755 /run/pulse

COPY start.sh /start.sh
COPY shairport-sync.conf.tmpl /shairport-sync.conf.tmpl
RUN chmod +x /start.sh

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD bash -lc 'pgrep -x shairport-sync >/dev/null && pgrep -f pulseaudio-dlna >/dev/null'

CMD ["/start.sh"]
