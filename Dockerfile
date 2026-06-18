FROM alpine:latest AS builder
RUN apk add --no-cache ca-certificates wget unzip curl
RUN wget -qO /tmp/xray.zip https://github.com/XTLS/Xray-core/releases/download/v26.5.9/Xray-linux-64.zip && \
    unzip -p /tmp/xray.zip xray > /usr/local/bin/xray && \
    chmod +x /usr/local/bin/xray && rm -rf /tmp/xray.zip

FROM envoyproxy/envoy:v1.30.1
USER root
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl python3 netcat-openbsd && rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/local/bin/xray /usr/local/bin/xray
COPY config.json /etc/xray.json
COPY envoy.yaml /etc/envoy/envoy.yaml
COPY index.html /var/www/html/index.html

EXPOSE 8080

HEALTHCHECK --interval=10s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Start sub-systems in order with loopback validation checks
CMD /usr/local/bin/xray run -c /etc/xray.json > /var/log/xray.log 2>&1 & \
    python3 -m http.server 8081 --directory /var/www/html > /var/log/http.log 2>&1 & \
    echo "Synchronizing container routing components..." && \
    while ! nc -z 127.0.0.1 10000; do sleep 0.5; done && \
    while ! nc -z 127.0.0.1 8081; do sleep 0.5; done && \
    echo "Core sub-systems running. Launching Envoy Proxy Engine..." && \
    exec envoy -c /etc/envoy/envoy.yaml --log-level warning
