#!/usr/bin/env bash

set -euo pipefail

# ==== KILL PORT 3000 ====
echo "Checking port 3000..."
PORT_PID=$(ss -ltnp | grep ':3000' | awk -F 'pid=' '{print $2}' | cut -d',' -f1 || true)

if [ -n "$PORT_PID" ]; then
    kill -9 "$PORT_PID"
    echo "Killed process on port 3000."
else
    echo "Port 3000 is free."
fi

# ==== SETUP VARIABLES ====
ROOT=$PWD

export IDENTITY_PATH="${IDENTITY_PATH:-$ROOT/swarm.pem}"
export GENSYN_RESET_CONFIG="${GENSYN_RESET_CONFIG:-}"
export CONNECT_TO_TESTNET=true
export ORG_ID="${ORG_ID:-}"
export HF_HUB_DOWNLOAD_TIMEOUT=120
export SWARM_CONTRACT="0x7745a8FE4b8D2D2c3BB103F8dCae822746F35Da0"
export HUGGINGFACE_ACCESS_TOKEN="None"
export MODEL_NAME="Qwen/Qwen2.5-Coder-0.5B-Instruct"

CPU_ONLY=true

# ==== COLORS ====
GREEN="\033[32m"
BLUE="\033[34m"
RED="\033[31m"
RESET="\033[0m"

echo_green() { echo -e "$GREEN$1$RESET"; }
echo_blue() { echo -e "$BLUE$1$RESET"; }
echo_red() { echo -e "$RED$1$RESET"; }

# ==== CREATE LOGS DIR ====
mkdir -p "$ROOT/logs"

# ==== MODAL LOGIN SETUP ====
if [ "$CONNECT_TO_TESTNET" = true ]; then
    echo_green ">> Starting modal-login server..."
    
    cd modal-login
    
    # Update SWARM_CONTRACT in .env
    ENV_FILE="$ROOT/modal-login/.env"
    sed -i "3s/.*/SWARM_CONTRACT_ADDRESS=$SWARM_CONTRACT/" "$ENV_FILE"
    
    # Start server in background
    yarn start >> "$ROOT/logs/yarn.log" 2>&1 &
    SERVER_PID=$!
    echo "Started server process: $SERVER_PID"
    sleep 5
    
    cd "$ROOT"
    
    # Wait for userData.json
    echo_green ">> Waiting for userData.json..."
    while [ ! -f "modal-login/temp-data/userData.json" ]; do
        sleep 5
    done
    echo "Found userData.json. Proceeding..."
    
    # Get ORG_ID
    ORG_ID=$(awk 'BEGIN { FS = "\"" } !/^[ \t]*[{}]/ { print $(NF - 1); exit }' modal-login/temp-data/userData.json)
    echo "Your ORG_ID is set to: $ORG_ID"
    export ORG_ID
    
    # Wait for API key activation
    echo "Waiting for API key to become activated..."
    while true; do
        STATUS=$(curl -s "http://localhost:3000/api/get-api-key-status?orgId=$ORG_ID")
        if [[ "$STATUS" == "activated" ]]; then
            echo "API key is activated! Proceeding..."
            break
        else
            echo "Waiting for API key to be activated..."
            sleep 5
        fi
    done
fi


# ==== CONFIG HANDLING ====
if [ ! -d "$ROOT/configs" ]; then
    mkdir "$ROOT/configs"
fi

if [ -f "$ROOT/configs/code-gen-swarm.yaml" ]; then
    if ! cmp -s "$ROOT/code_gen_exp/config/code-gen-swarm.yaml" "$ROOT/configs/code-gen-swarm.yaml"; then
        if [ -z "$GENSYN_RESET_CONFIG" ]; then
            echo_green ">> Found differences in config. Set GENSYN_RESET_CONFIG to reset."
        else
            echo_green ">> Backing up existing config..."
            mv "$ROOT/configs/code-gen-swarm.yaml" "$ROOT/configs/code-gen-swarm.yaml.bak"
            cp "$ROOT/code_gen_exp/config/code-gen-swarm.yaml" "$ROOT/configs/code-gen-swarm.yaml"
        fi
    fi
else
    cp "$ROOT/code_gen_exp/config/code-gen-swarm.yaml" "$ROOT/configs/code-gen-swarm.yaml"
fi

# ==== HUGGINGFACE LOGOUT ====
if ! hf auth logout > /dev/null 2>&1; then
    unset HF_TOKEN
    unset HUGGING_FACE_HUB_TOKEN
    hf auth logout > /dev/null 2>&1
fi

# ==== START SWARM ====
echo -en "$RESET"
echo_green ">> Good luck in the swarm!"
echo_blue ">> Star the repo: https://github.com/gensyn-ai/rl-swarm"

python3 -m code_gen_exp.runner.swarm_launcher \
    --config-path "$ROOT/code_gen_exp/config" \
    --config-name "code-gen-swarm.yaml"

wait
