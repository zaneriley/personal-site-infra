#!/bin/bash

set -euo pipefail

LOG_FILE="/var/log/k3s_install.log"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

handle_error() {
    log "Error occurred on line $1"
    exit 1
}

trap 'handle_error $LINENO' ERR

log "Starting k3s installation"

# Install k3s
log "Downloading and installing k3s"
if ! curl -sfL https://get.k3s.io | sh -; then
    log "Failed to install k3s"
    exit 1
fi

# Wait for k3s to be ready
log "Waiting for k3s to be ready"
timeout=300
start_time=$(date +%s)
until kubectl get nodes &> /dev/null; do
    current_time=$(date +%s)
    elapsed=$((current_time - start_time))
    if [ $elapsed -gt $timeout ]; then
        log "Timeout waiting for k3s to be ready"
        exit 1
    fi
    sleep 5
done

# Get the kubeconfig
log "Retrieving kubeconfig"
if ! sudo cat /etc/rancher/k3s/k3s.yaml > kubeconfig.yaml; then
    log "Failed to retrieve kubeconfig"
    exit 1
fi

log "k3s installation completed successfully"

# Install Helm
log "Installing Helm"
if ! curl -fsSL https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash; then
    log "Failed to install Helm"
    exit 1
fi
log "Helm installation completed successfully"

# Add Sealed Secrets repository
log "Adding Sealed Secrets Helm repository"
if ! helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets; then
    log "Failed to add Sealed Secrets Helm repository"
    exit 1
fi

# Update Helm repositories
log "Updating Helm repositories"
if ! helm repo update; then
    log "Failed to update Helm repositories"
    exit 1
fi

# Install Sealed Secrets controller
log "Installing Sealed Secrets controller"
if ! helm install sealed-secrets sealed-secrets/sealed-secrets -n kube-system; then
    log "Failed to install Sealed Secrets controller"
    exit 1
fi
log "Sealed Secrets controller installation completed successfully"

log "All installations completed successfully"