# --- Stage 1: Fetch Binaries ---
FROM alpine:latest AS fetcher
RUN apk add --no-cache curl unzip

# Download the latest Xray-Core
RUN XRAY_VERSION=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/') \
    && curl -L -o /tmp/xray.zip "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-64.zip" \
    && unzip /tmp/xray.zip -d /tmp/xray

# --- Stage 2: Final Production Image ---
FROM envoyproxy/envoy:v1.30-latest

# CRITICAL FIX: Switch to root to prevent permission errors during package install and supervisord execution
USER root

# Install Python (UI), Supervisor (Orchestration), and dependencies
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

# Create necessary directories
RUN mkdir -p /etc/envoy /etc/xray /var/www/html /var/log/supervisor

# Copy configuration files (Ensure your local files are named exactly like this)
COPY envoy.yaml /etc/envoy/envoy.yaml
COPY config.json /etc/xray/config.json
COPY index.html /var/www/html/index.html

# Expose the global port required by Cloud Run (mapped to 443 externally)
EXPOSE 8080

# CRITICAL FIX: Safely write supervisord config with autorestart flags
RUN printf "[supervisord]\n\
nodaemon=true\n\
user=root\n\
logfile=/dev/null\n\
pidfile=/var/run/supervisord.pid\n\
\n\
[program:envoy]\n\
command=envoy -c /etc/envoy/envoy.yaml\n\
stdout_logfile=/dev/stdout\n\
stdout_logfile_maxbytes=0\n\
stderr_logfile=/dev/stderr\n\
stderr_logfile_maxbytes=0\n\
autorestart=true\n\
\n\
[program:xray]\n\
command=xray -config /etc/xray/config.json\n\
stdout_logfile=/dev/stdout\n\
stdout_logfile_maxbytes=0\n\
stderr_logfile=/dev/stderr\n\
stderr_logfile_maxbytes=0\n\
autorestart=true\n\
\n\
[program:dashboard]\n\
command=python3 -m http.server 9000 --directory /var/www/html\n\
stdout_logfile=/dev/null\n\
stderr_logfile=/dev/stderr\n\
stderr_logfile_maxbytes=0\n\
autorestart=true\n" > /etc/supervisor/conf.d/supervisord.conf

# Start the Supervisor orchestration engine
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]