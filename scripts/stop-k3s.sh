#!/usr/bin/env bash

set -euo pipefail

# Define color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions for logging
log() { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"; }
error() { echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" >&2; }
warn() { echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"; }
info() { echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"; }

# Function to check if k3s is running
check_k3s_status() {
    if sudo systemctl is-active --quiet k3s; then
        return 0
    else
        return 1
    fi
}

# Function to stop k3s
stop_k3s() {
    log "Attempting to stop k3s service..."
    if sudo systemctl stop k3s; then
        log "k3s service stopped successfully."
    else
        error "Failed to stop k3s service. Please check the system logs for more information."
        exit 1
    fi
}

# Function to verify k3s has stopped
verify_k3s_stopped() {
    log "Verifying k3s service has stopped..."
    local max_attempts=10
    local attempt=1
    while check_k3s_status; do
        if [ $attempt -ge $max_attempts ]; then
            error "k3s service did not stop after $max_attempts attempts. Please investigate manually."
            exit 1
        fi
        warn "k3s is still running. Waiting 5 seconds before checking again (attempt $attempt/$max_attempts)..."
        sleep 5
        ((attempt++))
    done
    log "k3s service has been successfully stopped."
}

# Main function
main() {
    log "Starting k3s shutdown process..."

    if check_k3s_status; then
        stop_k3s
        verify_k3s_stopped
    else
        info "k3s service is not running. No action needed."
    fi

    log "k3s shutdown process completed."
}

# Run the main function
main