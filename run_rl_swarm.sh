#!/usr/bin/env bash

set -euo pipefail

ROOT=$PWD

export IDENTITY_PATH
export GENSYN_RESET_CONFIG
export CONNECT_TO_TESTNET=true
export ORG_ID
export HF_HUB_DOWNLOAD_TIMEOUT=120  # 2 minutes
export SWARM_CONTRACT="0x7745a8FE4b8D2D2c3BB103F8dCae822746F35Da0"
export HUGGINGFACE_ACCESS_TOKEN="None"

DEFAULT_IDENTITY_PATH="$ROOT"/swarm.pem
IDENTITY_PATH=${IDENTITY_PATH:-$DEFAULT_IDENTITY_PATH}

DOCKER=${DOCKER:-""}
GENSYN_RESET_CONFIG=${GENSYN_RESET_CONFIG:-""}

CPU_ONLY=true

# Set if successfully parsed from modal-login/temp-data/userData.json.
ORG_ID=${ORG_ID:-""}

GREEN_TEXT="\033[32m"
BLUE_TEXT="\033[34m"
RED_TEXT="\033[31m"
RESET_TEXT="\033[0m"

echo_green() { echo -e "$GREEN_TEXT$1$RESET_TEXT"; }
echo_blue() { echo -e "$BLUE_TEXT$1$RESET_TEXT"; }
echo_red() { echo -e "$RED_TEXT$1$RESET_TEXT"; }

# Create logs directory if it doesn't exist
mkdir -p "$ROOT/logs"

if [ "$CONNECT_TO_TESTNET" = true ]; then
    echo "Please login to create an Ethereum Server Wallet"
    
    cd modal-login || { echo "Folder modal-login not found"; exit 1; }

    # Thay trực tiếp SWARM_CONTRACT_ADDRESS trong .env (Linux)
    ENV_FILE="$PWD/.env"
    sed -i "3s/.*/SWARM_CONTRACT_ADDRESS=$SWARM_CONTRACT/" "$ENV_FILE"


    cd "$ROOT"

    echo_green ">> Waiting for modal userData.json to be created..."
    while [ ! -f "modal-login/temp-data/userData.json" ]; do
        sleep 5  # Wait for 5 seconds before checking again
    done
    echo "Found userData.json. Proceeding..."

    ORG_ID=$(awk 'BEGIN { FS = "\"" } !/^[ \t]*[{}]/ { print $(NF - 1); exit }' modal-login/temp-data/userData.json)
    echo "Your ORG_ID is set to: $ORG_ID"

    # Wait until the API key is activated by the client
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

HUGGINGFACE_ACCESS_TOKEN="None"
MODEL_NAME="Qwen/Qwen2.5-Coder-0.5B-Instruct"
export MODEL_NAME

#logout to prevent weird env issues, if it fails unset and try again
if ! hf auth logout > /dev/null 2>&1; then
    unset HF_TOKEN
    unset HUGGING_FACE_HUB_TOKEN
    # if it fails a second time, report stderr
    hf auth logout > /dev/null 2>&1
fi

echo -en $RESET_TEXT
echo_green ">> Good luck in the swarm!"
echo_blue ">> And remember to star the repo on GitHub! --> https://github.com/gensyn-ai/rl-swarm"

python3 -m code_gen_exp.runner.swarm_launcher \
    --config-path "$ROOT/code_gen_exp/config" \
    --config-name "code-gen-swarm.yaml" 

wait  # Keep script running until Ctrl+C
