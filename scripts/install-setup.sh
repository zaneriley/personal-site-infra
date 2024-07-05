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
sudo cat /etc/rancher/k3s/k3s.yaml > kubeconfig.yaml
chmod 600 kubeconfig.yaml
export KUBECONFIG=$(pwd)/kubeconfig.yaml
log "k3s installation completed successfully"


# Install FluxCD
log "Installing FluxCD"
if ! curl -s https://fluxcd.io/install.sh | sudo bash; then
    log "Failed to install FluxCD"
    exit 1
fi

# Check if GITHUB_USER is provided
if [ $# -eq 0 ]; then
    log "Error: GITHUB_USER argument is required"
    log "Usage: $0 <GITHUB_USER>"
    exit 1
fi
GITHUB_USER="$1"

# Check if GITHUB_USER is set
if [ -z "${GITHUB_USER}" ]; then
    log "Error: GITHUB_USER is not set"
    exit 1
fi

# Ensure KUBECONFIG is set
export KUBECONFIG=$(pwd)/kubeconfig.yaml

# Bootstrap FluxCD
log "Bootstrapping FluxCD"
if ! flux bootstrap github \
    --owner="$GITHUB_USER" \
    --repository=personal-site \
    --branch=main \
    --path=./kubernetes/clusters/local \
    --personal; then
    log "Failed to bootstrap FluxCD"
    exit 1
fi
log "FluxCD installation and bootstrap completed successfully"
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
if ! helm list -n kube-system | grep -q "sealed-secrets"; then
    if ! helm install sealed-secrets sealed-secrets/sealed-secrets -n kube-system; then
        log "Failed to install Sealed Secrets controller"
        exit 1
    fi
    log "Sealed Secrets controller installed successfully"
else
    log "Sealed Secrets controller is already installed"
fi

# Install NGINX Ingress Controller
log "Installing NGINX Ingress Controller"
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

if ! helm list -n ingress-nginx | grep -q "ingress-nginx"; then
    if ! helm install ingress-nginx ingress-nginx/ingress-nginx --namespace ingress-nginx --create-namespace; then
        log "Failed to install NGINX Ingress Controller"
        exit 1
    fi
    log "NGINX Ingress Controller installed successfully"
else
    log "NGINX Ingress Controller is already installed"
fi

# End of script
log "All components installed successfully"