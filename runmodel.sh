#!/usr/bin/env bash

# Script to run llama-server with multiple model configurations
# Usage: ./runmodel.sh [options] <model_name> [config_name]

set -euo pipefail # Exit on error, undefined vars, pipe failures

# Default config file
CONFIG_FILE="models.json"

# --- Edit these variables according to your setup ---

# Path to the llama-server executable
#LLAMA_SERVER_CMD="/usr/local/llama.cpp/bin/llama-server"

# Host Binding (Default: uses localhost (default for llama-server))
#IP_ADDRESS="127.0.0.1"

# Server Port (Default: 8080 (default for llama-server))
#PORT=8080

# ----------------------------------------
# system specific variables

export GOMP_CPU_AFFINITY="0-8"
export BLIS_NUM_THREADS=8

# --- Functions ---

log_info() { echo "[INFO] $*"; }
log_error() { echo "[ERROR] $*" >&2; }

validate_config_file() {
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "Configuration file '$CONFIG_FILE' not found"
        return 1
    fi
    if ! jq empty "$CONFIG_FILE" >/dev/null 2>&1; then
        log_error "Configuration file '$CONFIG_FILE' contains invalid JSON"
        jq empty "$CONFIG_FILE"
        return 1
    fi
    return 0
}

resolve_global_vars() {

    # --- Variable Resolution based on models.json globals ---
    local val
    # Resolve LLAMA_SERVER_CMD
    # If variable is not defined in script, try to get from JSON. If not in JSON, error.
    if [[ -v LLAMA_SERVER_CMD ]]; then
        : # Defined in script, use as is
    else
        val=$(jq -r '.globals.llama_server_cmd' "$CONFIG_FILE" 2>/dev/null)
        if [[ -z "$val" || "$val" == "null" ]]; then
            echo "[ERROR] LLAMA_SERVER_CMD not defined in script or models.json globals" >&2
            exit 1
        fi
        LLAMA_SERVER_CMD="$val"
    fi

    # Resolve IP_ADDRESS
    # If variable is not defined in script, try to get from JSON. If not in JSON, leave undefined.
    if [[ -v IP_ADDRESS ]]; then
        : # Defined in script, use as is
    else
        val=$(jq -r '.globals.ip_address' "$CONFIG_FILE" 2>/dev/null)
        if [[ -n "$val" && "$val" != "null" ]]; then
            IP_ADDRESS="$val"
        fi
    fi

    # Resolve PORT
    # If variable is not defined in script, try to get from JSON. If not in JSON, leave undefined.
    if [[ -v PORT ]]; then
        : # Defined in script, use as is
    else
        val=$(jq -r '.globals.port' "$CONFIG_FILE" 2>/dev/null)
        if [[ -n "$val" && "$val" != "null" ]]; then
            PORT="$val"
        fi
    fi

    # Resolve LD_LIBRARY_PATH
    val=$(jq -r '.globals.ld_library_path // empty' "$CONFIG_FILE" 2>/dev/null)
    if [[ -n "$val" ]]; then
        export LD_LIBRARY_PATH="${val}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
        log_info "LD_LIBRARY_PATH=$LD_LIBRARY_PATH"
    fi
}

run_model() {
    local model_name="$1"
    local config_name="$2"

    # Check if model exists in config
    local model_exists
    model_exists=$(jq -r --arg model "$model_name" '.models[] | select(.model == $model) | .model' "$CONFIG_FILE" 2>/dev/null)

    if [ -z "$model_exists" ] || [ "$model_exists" = "null" ]; then
        log_error "Model '$model_name' not found in configuration"
        return 1
    fi

    # Extract the specific config as JSON
    local config_data
    if [ -z "$config_name" ]; then
        config_data=$(jq -r --arg model "$model_name" '.models[] | select(.model == $model) | .configs[0] | @json' "$CONFIG_FILE" 2>/dev/null)
    else
        config_data=$(jq -r --arg model "$model_name" --arg config "$config_name" '.models[] | select(.model == $model) | .configs[] | select(.name == $config) | @json' "$CONFIG_FILE" 2>/dev/null)
    fi

    if [ -z "$config_data" ] || [ "$config_data" = "null" ]; then
        log_error "Configuration '$config_name' not found for model '$model_name'"
        return 1
    fi

    # Extract model path (file)
    local model_path
    model_path=$(jq -r --arg model "$model_name" '.models[] | select(.model == $model) | .file' "$CONFIG_FILE" 2>/dev/null)

    # Build command arguments using an array
    # We avoid 'eval' for security and proper quoting
    local -a cmd_args
    cmd_args=("$LLAMA_SERVER_CMD" "-m" "$model_path")

    # Add global overrides if defined
    if [ -n "${IP_ADDRESS:-}" ]; then
        cmd_args+=("--host" "$IP_ADDRESS")
    fi
    if [ -n "${PORT:-}" ]; then
        cmd_args+=("--port" "$PORT")
    fi

    # Add extra globals from models.json (excluding handled keys)
    # Excluded keys: llama_server_cmd, ip_address, port
    local key value
    while IFS='=' read -r key value; do
        if [ -n "$key" ]; then
            cmd_args+=("--${key}" "$value")
        fi
    done < <(jq -r '.globals // empty | to_entries | map(select(.key != "llama_server_cmd" and .key != "ip_address" and .key != "port" and .key != "ld_library_path")) | .[] | "\(.key)=\(.value)"' "$CONFIG_FILE" 2>/dev/null)

    # Add config parameters from JSON
    # We iterate over the JSON object keys/values safely
    while IFS='=' read -r key value; do
        if [ -n "$key" ]; then
            cmd_args+=("--${key}" "$value")
        fi
    done < <(echo "$config_data" | jq -r 'to_entries | map(select(.key != "name") | "\(.key)=\(.value)") | join("\n")')

    # Execute
    log_info "Running model '$model_name' with config '$config_name':"
    log_info "Command: ${cmd_args[*]}"
    
    # Use 'exec' to replace current shell with server process (better signal handling)
    exec "${cmd_args[@]}"
}

list_models() {
    echo "Available models and configurations:"
    # Updated path: .models[] instead of .[]
    jq -r '.models[] | "  \(.model): \(.configs | map(.name) | join(", "))"' "$CONFIG_FILE"
}

show_model_info() {
    local model_name="$1"
    local model_exists
    # Updated path: .models[] instead of .[]
    model_exists=$(jq -r --arg model "$model_name" '.models[] | select(.model == $model) | .model' "$CONFIG_FILE" 2>/dev/null)

    if [ -z "$model_exists" ] || [ "$model_exists" = "null" ]; then
        log_error "Model '$model_name' not found in configuration"
        return 1
    fi

    echo "Model: $model_name"
    # Updated path: .models[] instead of .[]
    echo "File:  $(jq -r --arg model "$model_name" '.models[] | select(.model == $model) | .file' "$CONFIG_FILE")"
    echo "Configurations:"
    # Updated path: .models[] instead of .[]
    jq -r --arg model "$model_name" '.models[] | select(.model == $model) | .configs[] | "  \(.name): \(. | to_entries | map(select(.key != "name") | "\(.key)=\(.value)") | join(", "))"' "$CONFIG_FILE"
}

print_usage() {
    cat << EOF
Usage: $0 [OPTIONS] <model_name> [config_name]

Run llama-server with specified model and configuration.

Options:
  -h, --help      Show this help message
  -l, --list      List all available models and configurations
  -i, --info      Show detailed information about a specific model
  -f, --file      Specify configuration file (default: models.json)

Examples:
  $0 model.gguf
  $0 model.gguf code
  $0 -l
  $0 -i model.gguf
  $0 -f custom_models.json model.gguf
EOF
}

# --- Argument Parsing ---
# Use GNU getopt for long options. 
# Note: On macOS, install 'coreutils' to ensure 'getopt' supports --long
PARSED=$(getopt -o hli:f: --long help,list,info:,file: -n "$0" -- "$@")
if [ $? -ne 0 ]; then
    log_error "Failed to parse arguments"
    print_usage
    exit 1
fi

eval set -- "$PARSED"

# Initialize variables
ACTION=""
MODEL_NAME=""
CONFIG_NAME=""

# Process options
while true; do
    case "$1" in
        -h|--help)
            print_usage
            exit 0
            ;;
        -l|--list)
            ACTION="list"
            shift
            ;;
        -i|--info)
            ACTION="info"
            MODEL_NAME="${2:-}"  # FIX: Safe expansion for unset variable
            shift 2
            ;;
        -f|--file)
            CONFIG_FILE="${2:-}" # FIX: Safe expansion for unset variable
            shift 2
            ;;
        --)
            shift
            break
            ;;
        *)
            log_error "Internal error!"
            exit 1
            ;;
    esac
done

# Validate configuration file exists and is valid
if ! validate_config_file; then
    exit 1
fi

# resolve global variables based on models.json globals 
resolve_global_vars

# Process remaining positional arguments
if [ -z "$ACTION" ]; then
    MODEL_NAME="${1:-}"
    CONFIG_NAME="${2:-}"
fi

# --- Main Logic ---
case "$ACTION" in
    list)
        list_models
        exit 0
        ;;
    info)
        if [ -z "$MODEL_NAME" ]; then
            log_error "Model name required for --info"
            print_usage
            exit 1
        fi
        show_model_info "$MODEL_NAME"
        exit 0
        ;;
    "")
        if [ -z "$MODEL_NAME" ]; then
            log_error "Model name required"
            print_usage
            exit 1
        fi
        run_model "$MODEL_NAME" "$CONFIG_NAME"
        # If we get here, the server exited normally (e.g. killed via signal)
        exit 0
        ;;
    *)
        log_error "Unknown action: $ACTION"
        exit 1
        ;;
esac
