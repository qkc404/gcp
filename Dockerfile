# ==========================================
# STAGE 1: FETCH BINARIES
# ==========================================
FROM alpine:latest AS fetcher
RUN apk add --no-cache curl unzip

# Download the latest Xray-Core
RUN XRAY_VERSION=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/') \
    && curl -L -o /tmp/xray.zip "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-64.zip" \
    && unzip /tmp/xray.zip -d /tmp/xray

# ==========================================
# STAGE 2: FINAL PRODUCTION IMAGE
# ==========================================
FROM envoyproxy/envoy:v1.30-latest

# Switch to root to prevent permission errors during package install
USER root

# Install Python (UI), Supervisor (Orchestration), and clean apt cache
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    supervisor \
    python3 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy Xray binaries and grant execution rights
COPY --from=fetcher /tmp/xray/xray /usr/local/bin/xray
COPY --from=fetcher /tmp/xray/geosite.dat /usr/local/share/xray/geosite.dat
COPY --from=fetcher /tmp/xray/geoip.dat /usr/local/share/xray/geoip.dat
RUN chmod +x /usr/local/bin/xray

# Create all necessary directories
RUN mkdir -p /etc/envoy /etc/xray /var/www/html /var/log/supervisor /etc/supervisor/conf.d

# Copy configuration files AND your custom UI
COPY envoy.yaml /etc/envoy/envoy.yaml
COPY config.json /etc/xray/config.json
COPY index.html /var/www/html/index.html

# Expose the global port required by Cloud Run mapping
EXPOSE 8080

# Safely write supervisord config with exact absolute paths and the correct 'xray run' syntax
RUN printf "[supervisord]\n\
nodaemon=true\n\
user=root\n\
logfile=/dev/null\n\
pidfile=/var/run/supervisord.pid\n\
\n\
[program:envoy]\n\
command=/usr/local/bin/envoy -c /etc/envoy/envoy.yaml\n\
stdout_logfile=/dev/stdout\n\
stdout_logfile_maxbytes=0\n\
stderr_logfile=/dev/stderr\n\
stderr_logfile_maxbytes=0\n\
autorestart=true\n\
\n\
[program:xray]\n\
command=/usr/local/bin/xray run -config /etc/xray/config.json\n\
stdout_logfile=/dev/stdout\n\
stdout_logfile_maxbytes=0\n\
stderr_logfile=/dev/stderr\n\
stderr_logfile_maxbytes=0\n\
autorestart=true\n\
\n\
[program:dashboard]\n\
command=/usr/bin/python3 -m http.server 9000 --directory /var/www/html\n\
stdout_logfile=/dev/null\n\
stderr_logfile=/dev/stderr\n\
stderr_logfile_maxbytes=0\n\
autorestart=true\n" > /etc/supervisor/conf.d/supervisord.conf

# Start the Supervisor orchestration engine
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
