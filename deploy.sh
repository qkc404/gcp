#!/bin/bash

# ==========================================
# ADVANCED H2O-ENVOY DEPLOYER - SAEKA PRO
# ==========================================

BOLD='\033[1m'
RESET='\033[0m'
GREEN='\033[1;32m'
RED='\033[1;31m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
MAGENTA='\033[1;35m'
WHITE='\033[1;37m'
GRAY='\033[1;30m'

clear

echo ""
echo -e "  ${BOLD}${WHITE}╭────────────────────────────────────────╮${RESET}"
echo -e "  ${BOLD}${WHITE}│          SAEKA GCP H2O-ENVOY           │${RESET}"
echo -e "  ${BOLD}${WHITE}╰────────────────────────────────────────╯${RESET}"
echo -e "   ${MAGENTA}  DEVELOPED BY SAEKA TOJIRP${RESET}"
echo -e "   ${GREEN}  fb.com/saekacutiee${RESET}"
echo ""

PROJECT_ID=$(gcloud config get-value project 2>/dev/null | tr -d '[:space:]')
if [ -z "$PROJECT_ID" ]; then
    echo -e "  ${RED}✖ ERROR: No active GCP project found.${RESET}"
    echo -e "  Please run: ${CYAN}gcloud config set project [YOUR_PROJECT_ID]${RESET}"
    exit 1
fi
echo -e "  ${CYAN}[INIT]${RESET} ACTIVE PROJECT : ${GREEN}${PROJECT_ID}${RESET}"
echo ""

read -r -p "$(echo -e "  ${CYAN}➜ Enter Service Name [default: saeka-server]: ${RESET}")" INPUT_NAME
SERVICE_NAME=${INPUT_NAME:-saeka-server}

echo ""
echo -e "  ${CYAN}➜ SELECT HARDWARE PROFILE:${RESET}"
echo -e "    ${YELLOW}1)${RESET} BROWSING     ${GRAY}(1 vCPU / 2Gi RAM)${RESET}"
echo -e "    ${YELLOW}2)${RESET} STREAMING    ${GRAY}(2 vCPU / 4Gi RAM)${RESET}"
echo -e "    ${YELLOW}3)${RESET} GAMING       ${GRAY}(4 vCPU / 8Gi RAM)${RESET}"
echo -e "    ${YELLOW}4)${RESET} ULTRA        ${GRAY}(8 vCPU / 16Gi RAM)${RESET}"
echo ""
read -r -p "$(echo -e "  ${CYAN}➜ CHOICE [default: 2]: ${RESET}")" MODE_CHOICE

case "$MODE_CHOICE" in
    1) CPU="1"; RAM="2Gi"; MODE="BROWSING"; MAX_INSTANCES="5";;
    3) CPU="4"; RAM="8Gi"; MODE="GAMING"; MAX_INSTANCES="4";;
    4) CPU="8"; RAM="16Gi"; MODE="ULTRA"; MAX_INSTANCES="2";;
    *) CPU="2"; RAM="4Gi"; MODE="STREAMING"; MAX_INSTANCES="4";;
esac

echo ""
echo -e "  ${CYAN}➜ SELECTED PROFILE: ${GREEN}${MODE} (${CPU} vCPU / ${RAM})${RESET}"
echo ""

echo -e "  ${MAGENTA}▶ STAGE 1: COMPILING CONTAINER IMAGE VIA CLOUD BUILD...${RESET}"
# The > /dev/null 2>&1 swallows all logs, keeping the terminal clean
gcloud builds submit --tag "gcr.io/${PROJECT_ID}/${SERVICE_NAME}" --project="$PROJECT_ID" --quiet > /dev/null 2>&1

if [ $? -ne 0 ]; then 
    echo -e "  ${RED}✖ ERROR: BUILD FAILED. Run without redirection to debug.${RESET}"
    exit 1
fi
echo -e "  ${GREEN}✔ CONTAINER BUILD SUCCESSFUL${RESET}"
echo ""

echo -e "  ${MAGENTA}▶ STAGE 2: DEPLOYING TO GOOGLE CLOUD RUN (STANDARD H2O LAYER)...${RESET}"
# Swallowing deployment logs for a seamless UI experience
gcloud run deploy "$SERVICE_NAME" \
  --image "gcr.io/${PROJECT_ID}/${SERVICE_NAME}" \
  --platform managed --region us-central1 \
  --cpu "$CPU" --memory "$RAM" --port 8080 \
  --concurrency 1000 --cpu-boost \
  --timeout 3600 --min-instances 1 --max-instances "$MAX_INSTANCES" \
  --allow-unauthenticated --project="$PROJECT_ID" --quiet > /dev/null 2>&1

if [ $? -ne 0 ]; then 
    echo -e "  ${RED}✖ ERROR: DEPLOYMENT FAILED.${RESET}"
    exit 1
fi

SERVICE_URL=$(gcloud run services describe "$SERVICE_NAME" --region us-central1 --project="$PROJECT_ID" --format='value(status.url)' 2>/dev/null)

echo ""
echo -e "  ${BOLD}${GREEN}╭────────────────────────────────────────╮${RESET}"
echo -e "  ${BOLD}${GREEN}│      DEPLOYMENT FULLY SUCCESSFUL       │${RESET}"
echo -e "  ${BOLD}${GREEN}╰────────────────────────────────────────╯${RESET}"
echo ""
echo -e "  ${CYAN}▶ SERVER NAME: ${WHITE}SAEKA GCP SERVER${RESET}"
echo -e "  ${CYAN}▶ LINK       : ${GREEN}fb.com/saekacutiee${RESET}"
echo -e "  ${CYAN}▶ URL/HOST   : ${GREEN}${SERVICE_URL}${RESET}"
echo -e "  ${CYAN}▶ EDGE PORT  : ${GREEN}443${RESET}"
echo -e "  ${CYAN}▶ ALPN SPEEDS: ${GREEN}HTTP/1.1 $\rightarrow$ HTTP/2 $\rightarrow$ HTTP/3 (H3 Native Edge)${RESET}"
echo -e "  ${CYAN}▶ PROTOCOLS  : ${GREEN}VLESS / VMESS / TROJAN / SHADOWSOCKS${RESET}"
echo ""
