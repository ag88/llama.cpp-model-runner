# `runmodel.sh` a simple model launcher for llama.cpp / llama-server

## Overview

`runmodel.sh` is a wrapper script designed to simplify running `llama-server` from the `llama.cpp` project. It manages multiple LLM models and their respective inference configurations via a centralized JSON file. This script handles argument parsing, configuration validation, and dynamic command construction, allowing users to launch different models with specific hyperparameters (temperature, context size, etc.) without editing the server binary arguments manually.

## Prerequisites

Before running the script, ensure the following dependencies are installed on your system:

1.  **Bash**: The script is written for Bash (`#!/usr/bin/env bash`).
2.  **jq**: This utility is **required** to parse the `models.json` configuration file.
    *   *Linux (Debian/Ubuntu)*: `sudo apt-get install jq`
    *   *Linux (RHEL/CentOS)*: `sudo yum install jq`
    *   *macOS*: `brew install jq`
3.  **GNU getopt**: Required for parsing command-line options (Note: macOS requires `coreutils` to get the GNU version of `getopt`).
    `brew install coreutils`
4.  **llama.cpp**: The `llama-server` binary must be installed and accessible.

## Configuration

The script relies on two primary configuration mechanisms: the `models.json` file located in the same directory for model definitions and parameters, and specific variables defined within the script for environment overrides.  

### models.json

The `models.json` file defines available models, their file paths, and specific inference configurations. Below is the expected structure of the `models.json` file used by this wrapper script:

```json
{
  "globals": {
    "llama_server_cmd": "/usr/local/llama.cpp/bin/llama-server",
    "ip_address": "127.0.0.1",
    "port": 8080
  },
  "models": [
    {
      "model": "gemma-4-26B-A4B-it-UD-Q4_K_M.gguf",
      "file": "gemma-4-26B-A4B-it-UD-Q4_K_M.gguf",
      "configs": [
        {
          "name": "default",
          "temp": 1.0,
          "top-p": 0.95,
          "top-k": 64
        }
      ]
    },
    {
      "model": "Qwen3.5-35B-A3B-Q4_K_M.gguf",
      "file": "Qwen3.5-35B-A3B-Q4_K_M.gguf",
      "configs": [
        {
          "name": "code",
          "ctx-size": 16384,
          "temp": 0.6,
          "top-p": 0.95,
          "top-k": 20,
          "min-p": 0.00
        },
        {
          "name": "general",
          "ctx-size": 16384,
          "temp": 1.0,
          "top-p": 0.95,
          "top-k": 20,
          "min-p": 0.00
        }
      ]
    }
  ]
}
```

### The "models" Object (Array)

The `models` array is the core definition of available LLMs. It contains a list of objects, where each object represents a specific model file and its available tuning configurations.

*   **`model`**: The display name used to invoke the model via the CLI (e.g., `gemma-4-26B...`).
*   **`file`**: The relative or absolute path to the actual .gguf model file on disk.
*   **`configs`**: An array of configuration presets for that specific model. Each config includes:
    *   **`name`**: The specific configuration name (e.g., `code`, `default`, `general`) used in the CLI.
    *   **Parameters**: Key-value pairs such as `temp`, `top-p`, `top-k`, `ctx-size`, and `min-p` which map directly to `llama-server` arguments.
    *   *Note:* If no specific config name is provided when running the script, the script defaults to the first config in the list (`configs[0]`).

### The "globals" Object

The `globals` object defines server-wide defaults that apply to all models unless overridden in the script.

*   **`llama_server_cmd`**: The full path to the `llama-server` executable.
*   **`ip_address`**: The hostname or IP address the server should bind to (default is `127.0.0.1`).
*   **`port`**: The TCP port number for the server to listen on (default is `8080`).
*   **Other Globals**: Any additional keys in this object (excluding `llama_server_cmd`, `ip_address`, `port`) will be passed as command-line arguments to the server.

### Configuration Overrides

While `models.json` provides the defaults, you can override specific settings directly within the `runmodel.sh` script file. This allows you to change paths or ports without editing the JSON file.

To modify these values, edit the script `runmodel.sh` between the following markers:

```bash
# --- Edit these variables according to your setup ---

# Path to the llama-server executable
LLAMA_SERVER_CMD="/usr/local/llama.cpp/bin/llama-server"

# Host Binding (Default: uses localhost (default for llama-server))
#IP_ADDRESS="127.0.0.1"

# Server Port (Default: 8080 (default for llama-server))
#PORT=8080

# ----------------------------------------
```

**Script Environment Variables:**
The following variables defined in the block above take precedence over the `globals` object in `models.json`:

*   **`LLAMA_SERVER_CMD`**: Overrides the path to the server binary defined in `models.json`. Predefined in the script, required.
    Comment that in the script to use the `models.json` value.
*   **`IP_ADDRESS`**: Overrides the bind IP address. This variable is optional; if commented out, the JSON default is used.
*   **`PORT`**: Overrides the server port. This variable is optional; if commented out, the JSON default is used.

*Note: If these variables are not defined in the script (or are commented out), the script attempts to resolve them from `models.json`.*

## Installation & Running

### 1. Installation
Place the `runmodel.sh` script and `models.json` in the same directory. Ensure the script is executable:

```bash
chmod +x runmodel.sh
```

### 2. Usage Syntax

```bash
./runmodel.sh [OPTIONS] <model_name> [config_name]
```

*   **`OPTIONS`**: Flags like `-h`, `-l`, `-i`, `-f`.
*   **`model_name`**: The value of the `model` key in `models.json`.
*   **`config_name`**: The value of the `name` key inside a specific model's `configs` array (optional; defaults to the first config).

### 3. Available Options

| Option | Flag | Description |
| :--- | :--- | :--- |
| **Help** | `-h`, `--help` | Display usage instructions. |
| **List** | `-l`, `--list` | List all available models and their configurations. |
| **Info** | `-i`, `--info` | Show detailed configuration info for a specific model. |
| **File** | `-f`, `--file` | Specify a custom configuration JSON file (default: `models.json`). |

## Examples

**List available models:**
```bash
./runmodel.sh -l
```

**Run a model with its default configuration:**
```bash
./runmodel.sh gemma-4-26B-A4B-it-UD-Q4_K_M.gguf
```

**Run a model with a specific configuration (e.g., "code"):**
```bash
./runmodel.sh Qwen3.5-35B-A3B-Q4_K_M.gguf code
```

**Show detailed info for a specific model:**
```bash
./runmodel.sh -i Qwen3.5-35B-A3B-Q4_K_M.gguf
```

**Run using a custom configuration file:**
```bash
./runmodel.sh -f custom_models.json Qwen3.5-35B-A3B-Q4_K_M.gguf
```
