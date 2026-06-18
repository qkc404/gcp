#!/bin/bash

BOLD='\033[1m'; RESET='\033[0m'
GREEN='\033[1;32m'; RED='\033[1;31m'; CYAN='\033[1;36m'
YELLOW='\033[1;33m'; BLUE='\033[1;34m'

loading() {
    local text="$1"
    local spin="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
    for ((i=0; i<3; i++)); do
        for ((j=0; j<${#spin}; j++)); do
            echo -ne "\r${CYAN}${spin:$j:1} ${text}...${RESET}"
            sleep 0.05
        done
    done
    echo -ne "\r${GREEN}DONE: ${text}${RESET}\n"
}

clear
echo -e "${BLUE}────────────────────────────────────────────────────${RESET}"
echo -e "${CYAN}   ENVOY + XRAY CLOUD RUN AUTOMATOR ENGINE          ${RESET}"
echo -e "${BLUE}────────────────────────────────────────────────────${RESET}"

PROJECT_ID=$(gcloud config get-value project 2>/dev/null | tr -d '[:space:]')
if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}ERROR: No active authenticated Google Cloud context discovered.${RESET}"
    exit 1
fi

# Assert core files exist to prevent build errors
for file in config.json envoy.yaml Dockerfile index.html; do
    if [ ! -f "$file" ]; then
        echo -e "${RED}CRITICAL COMPONENT MISSING: File '$file' must be present.${RESET}"
        exit 1
    fi
done

read -r -p "$(echo -e "${CYAN}  ENTER SERVICE NAME [envoy-vless]: ${RESET}")" INPUT_NAME
SERVICE_NAME=${INPUT_NAME:-envoy-vless}

echo -e "\n${CYAN}[DETECT] Discovering available regional locations...${RESET}"
AVAILABLE_REGIONS=($(gcloud compute regions list --format="value(name)" 2>/dev/null))
if [ ${#AVAILABLE_REGIONS[@]} -eq 0 ]; then
    AVAILABLE_REGIONS=("us-central1" "us-east1" "europe-west1" "asia-east1" "us-west1")
fi

for index in "${!AVAILABLE_REGIONS[@]}"; do
    echo -e "  ${YELLOW}$((index+1)))${RESET} ${AVAILABLE_REGIONS[$index]}"
done
echo -e ""
read -r -p "$(echo -e "${CYAN}[SELECT] Choose regional target number [1]: ${RESET}")" REGION_CHOICE
if [[ -z "$REGION_CHOICE" || ! "$REGION_CHOICE" =~ ^[0-9]+$ || "$REGION_CHOICE" -gt ${#AVAILABLE_REGIONS[@]} ]]; then
    SELECTED_REGION="${AVAILABLE_REGIONS[0]}"
else
    SELECTED_REGION="${AVAILABLE_REGIONS[$((REGION_CHOICE-1))]}"
fi

echo -e "\n${CYAN}  COMPILING TARGET DEPLOYMENT CONTAINER VIA CLOUD BUILD... ${RESET}"
gcloud builds submit --tag "gcr.io/${PROJECT_ID}/${SERVICE_NAME}" . --quiet > build.log 2>&1
if [ $? -ne 0 ]; then
    echo -e "${RED}BUILD PROCESS ERROR ENCOUNTERED! Raw Log Tail:${RESET}"
    tail -n 20 build.log
    exit 1
fi

loading "PROVISIONING SERVERLESS EDGE SUITE VIA GOOGLE CLOUD RUN"
gcloud run deploy "$SERVICE_NAME" \
  --image "gcr.io/${PROJECT_ID}/${SERVICE_NAME}" \
  --platform managed \
  --region "$SELECTED_REGION" \
  --cpu "2" \
  --memory "4Gi" \
  --port 8080 \
  --concurrency 1000 \
  --cpu-boost \
  --no-cpu-throttling \
  --timeout 3600 \
  --min-instances 1 \
  --max-instances 5 \
  --allow-unauthenticated \
  --quiet > deploy.log 2>&1

if [ $? -ne 0 ]; then
    echo -e "${RED}DEPLOYMENT FAILURE: Gcloud container deployment rejected.${RESET}"
    tail -n 20 deploy.log
    exit 1
fi

SERVICE_URL=$(gcloud run services describe "$SERVICE_NAME" --platform managed --region "$SELECTED_REGION" --format="value(status.url)" | sed 's/https:\/\///g')
UUID="saeka"

echo -e "\n${GREEN}🚀 INFRASTRUCTURE COMPILING SUCCESSFUL! RAW EXPORT LINKS:${RESET}"
echo -e "${BLUE}────────────────────────────────────────────────────${RESET}"
echo -e "${YELLOW}WebSocket (WS):${RESET}\nvless://${UUID}@${SERVICE_URL}:443?encryption=none&security=tls&sni=${SERVICE_URL}&type=ws&path=%2Fvless-saeka-ws#SAEKA-ENVOY-WS\n"
echo -e "${YELLOW}HTTPUpgrade (HU):${RESET}\nvless://${UUID}@${SERVICE_URL}:443?encryption=none&security=tls&sni=${SERVICE_URL}&type=httpupgrade&path=%2Fvless-saeka-hu#SAEKA-ENVOY-HU\n"
echo -e "${YELLOW}gRPC Transport:${RESET}\nvless://${UUID}@${SERVICE_URL}:443?encryption=none&security=tls&sni=${SERVICE_URL}&type=grpc&serviceName=vless-saeka-grpc#SAEKA-ENVOY-gRPC\n"
echo -e "${YELLOW}xhttp Stream:${RESET}\nvless://${UUID}@${SERVICE_URL}:443?encryption=none&security=tls&sni=${SERVICE_URL}&type=xhttp&path=%2Fvless-saeka-xhttp#SAEKA-ENVOY-XHTTP"
echo -e "${BLUE}────────────────────────────────────────────────────${RESET}"