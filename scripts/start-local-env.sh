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

# Function to check dependencies
check_dependencies() {
    local deps=("kubectl" "k3s" "helm")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            error "$dep is not installed. Please install it and try again."
            exit 1
        fi
    done
    log "All dependencies are installed."
}

# Function to start k3s
start_k3s() {
    log "Starting k3s..."
    if sudo systemctl is-active --quiet k3s; then
        info "k3s is already running."
    else
        sudo systemctl start k3s
        sleep 10  # Wait for k3s to initialize
    fi
    log "k3s started successfully."
}

# Function to apply Kubernetes resources
apply_resources() {
    log "Applying Kubernetes resources..."
    
    if ! kubectl apply -f kubernetes/base/namespace.yaml; then
        error "Failed to create namespace. Check your KUBECONFIG and cluster access."
        exit 1
    fi
    
    if ! kubectl apply -k .; then
        error "Failed to apply kustomization. Please check your Kubernetes manifests."
        exit 1
    fi
    
    log "Kubernetes resources applied successfully."
}

# Function to verify deployments
verify_deployments() {
    log "Verifying deployments..."
    local deployments=("personal-site-blue" "personal-site-green")
    for deployment in "${deployments[@]}"; do
        if ! kubectl -n personal-site rollout status deployment/"$deployment" --timeout=120s; then
            error "Deployment $deployment failed to roll out. Check the logs for more information."
            kubectl -n personal-site logs -l app=personal-site --tail=50
            exit 1
        fi
    done
    log "All deployments are running."
}

# Function to verify ingress
verify_ingress() {
    log "Verifying ingress..."
    if ! kubectl -n personal-site get ingress personal-site &> /dev/null; then
        error "Ingress 'personal-site' not found. Check your ingress configuration."
        exit 1
    fi
    log "Ingress is set up correctly."
}

# Function to set up port forwarding
setup_port_forwarding() {
    log "Setting up port forwarding..."
    if ! kubectl -n personal-site port-forward svc/personal-site-green 8000:80 &> /dev/null & then
        error "Failed to set up port forwarding. Check if the service exists and is running."
        exit 1
    fi
    log "Port forwarding set up. You can access the application at http://localhost:8000"
}

# Function to display resource usage
show_resource_usage() {
    log "Displaying resource usage..."
    kubectl top nodes
    kubectl top pods -n personal-site
}

# Main function to orchestrate the local environment setup
main() {
    log "Starting local environment setup..."
    
    check_dependencies
    start_k3s
    apply_resources
    verify_deployments
    verify_ingress
    setup_port_forwarding
    show_resource_usage
    
    log "Local environment is up and running!"
    info "Use 'kubectl logs -n personal-site <pod-name>' to view application logs."
    info "Use 'kubectl get all -n personal-site' to see all resources in the namespace."
    info "Press Ctrl+C to stop port forwarding and exit."
    
    # Keep the script running to maintain port forwarding
    wait
}

# Run the main function
main

# Trap to handle script exit
trap 'log "Stopping local environment..."; kubectl -n personal-site delete svc/personal-site-green &> /dev/null; log "Local environment stopped."' EXIT