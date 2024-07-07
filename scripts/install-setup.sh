#!/bin/bash

set -euo pipefail

GITHUB_USER=""

# Configuration variables
KUBECONFORM_VERSION="0.6.6"
KUBESCORE_VERSION="v1.18.0"

LOG_FILE="${K3S_INSTALL_LOG_FILE:-/tmp/k3s_install.log}"

# Check if GITHUB_USER is provided
if [ "$#" -eq 0 ]; then
    echo "Error: GITHUB_USER is required"
    echo "Usage: $0 <GITHUB_USER> [OPTIONS]"
    exit 1
fi

# Set GITHUB_USER from the first argument
GITHUB_USER="$1"
shift  # Remove the first argument (GITHUB_USER) from the argument list

check_kubeconfig() {
    if [ ! -f "$(pwd)/kubeconfig.yaml" ]; then
        log "Error: kubeconfig file not found. Make sure K3s installation was successful."
        return 1
    fi
}

# Logging and error handling functions
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

handle_error() {
    log "Error occurred on line $1"
    exit 1
}

cleanup() {
    log "Cleaning up..."
    # Add cleanup tasks here if needed
}

# Installation helper functions
install_tool() {
    local tool_name=$1
    local install_command=$2
    
    log "Installing $tool_name"
    if eval "$install_command"; then
        log "$tool_name installed successfully"
    else
        log "Failed to install $tool_name"
        return 1
    fi
}

add_helm_repo() {
    local repo_name=$1
    local repo_url=$2
    
    log "Adding Helm repository: $repo_name"
    if helm repo add "$repo_name" "$repo_url"; then
        log "Helm repository $repo_name added successfully"
    else
        log "Failed to add Helm repository $repo_name"
        return 1
    fi
}

install_helm_chart() {
    local chart_name=$1
    local repo_name=$2
    local namespace=$3
    
    log "Installing Helm chart: $chart_name"
    if ! helm list -n "$namespace" | grep -q "$chart_name"; then
        if helm install "$chart_name" "$repo_name/$chart_name" -n "$namespace" --create-namespace; then
            log "$chart_name installed successfully"
        else
            log "Failed to install $chart_name"
            return 1
        fi
    else
        log "$chart_name is already installed"
    fi
}

# Component installation functions
install_k3s() {
    log "Downloading and installing k3s"
    if ! curl -sfL https://get.k3s.io | sh -; then
        log "Failed to install k3s"
        return 1
    fi

    log "Setting correct permissions for k3s config"
    sudo chmod 644 /etc/rancher/k3s/k3s.yaml

    log "Waiting for k3s to be ready"
    timeout=600  # 10 minutes
    start_time=$(date +%s)

    until sudo kubectl get nodes 2>&1 | tee -a "$LOG_FILE" | grep -q "Ready"; do
        current_time=$(date +%s)
        elapsed=$((current_time - start_time))
        if [ $elapsed -gt $timeout ]; then
            log "Timeout waiting for k3s to be ready"
            log "K3s status: $(systemctl is-active k3s)"
            log "K3s logs: $(journalctl -u k3s -n 50)"
            return 1
        fi
        if ! pgrep k3s > /dev/null; then
            log "K3s process is not running"
            log "K3s status: $(systemctl is-active k3s)"
            log "K3s logs: $(journalctl -u k3s -n 50)"
            return 1
        fi
        log "Still waiting for k3s to be ready... (${elapsed}s elapsed)"
        sleep 10
    done

    log "K3s is ready"
    sudo kubectl get nodes

    log "Retrieving kubeconfig"
    sudo cp /etc/rancher/k3s/k3s.yaml kubeconfig.yaml
    sudo chown "$USER":"$USER" kubeconfig.yaml
    chmod 600 kubeconfig.yaml
    export KUBECONFIG
    KUBECONFIG=$(pwd)/kubeconfig.yaml
    log "k3s installation completed successfully"
}

install_flux() {
    log "Installing FluxCD"
    if ! curl -s https://fluxcd.io/install.sh | sudo bash; then
        log "Failed to install FluxCD"
        return 1
    fi

    log "Bootstrapping FluxCD"
    if ! KUBECONFIG=$(pwd)/kubeconfig.yaml flux bootstrap github \
        --owner="$GITHUB_USER" \
        --repository=personal-site \
        --branch=main \
        --path=./kubernetes/clusters/local \
        --personal; then
        log "Failed to bootstrap FluxCD"
        return 1
    fi
    log "FluxCD installation and bootstrap completed successfully"
}

install_helm() {
    install_tool "Helm" "
        curl -fsSL https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
    " || return 1
}

install_sealed_secrets() {
    add_helm_repo "sealed-secrets" "https://bitnami-labs.github.io/sealed-secrets" || return 1
    helm repo update
    install_helm_chart "sealed-secrets" "sealed-secrets" "kube-system" || return 1
}

install_nginx_ingress() {
    add_helm_repo "ingress-nginx" "https://kubernetes.github.io/ingress-nginx" || return 1
    helm repo update
    install_helm_chart "ingress-nginx" "ingress-nginx" "ingress-nginx" || return 1
}

install_kubeconform() {
    install_tool "kubeconform" "
        wget https://github.com/yannh/kubeconform/releases/download/v${KUBECONFORM_VERSION}/kubeconform-linux-amd64.tar.gz &&
        tar xf kubeconform-linux-amd64.tar.gz &&
        sudo mv kubeconform /usr/local/bin &&
        rm kubeconform-linux-amd64.tar.gz
    " || return 1
}

install_kubescore() {
    install_tool "kube-score" "
        wget https://github.com/zegl/kube-score/releases/download/v${KUBESCORE_VERSION}/kube-score_${KUBESCORE_VERSION}_linux_amd64 &&
        chmod +x kube-score_${KUBESCORE_VERSION}_linux_amd64 &&
        sudo mv kube-score_${KUBESCORE_VERSION}_linux_amd64 /usr/local/bin/kube-score
    " || return 1
}

# Usage function
usage() {
    echo "Usage: $0 [OPTIONS] <GITHUB_USER>"
    echo "Options:"
    echo "  --skip-shellcheck  Skip ShellCheck installation"
    echo "  --skip-k3s         Skip K3s installation"
    echo "  --skip-flux        Skip FluxCD installation"
    echo "  --skip-helm        Skip Helm installation"
    echo "  --skip-sealed-secrets  Skip Sealed Secrets installation"
    echo "  --skip-nginx       Skip NGINX Ingress Controller installation"
    echo "  --skip-kubeconform     Skip kubeconform installation"
    echo "  --skip-kubescore   Skip kube-score installation"
    echo "  -h, --help         Display this help message"
}

# Main script execution
main() {
    local skip_shellcheck=false
    local skip_k3s=false
    local skip_flux=false
    local skip_helm=false
    local skip_sealed_secrets=false
    local skip_nginx=false
    local skip_kubeconform=false
    local skip_kubescore=false

    # Parse command-line options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-shellcheck) skip_shellcheck=true ;;
            --skip-k3s) skip_k3s=true ;;
            --skip-flux) skip_flux=true ;;
            --skip-helm) skip_helm=true ;;
            --skip-sealed-secrets) skip_sealed_secrets=true ;;
            --skip-nginx) skip_nginx=true ;;
            --skip-kubeconform) skip_kubeconform=true ;;
            --skip-kubescore) skip_kubescore=true ;;
            -h|--help) usage; exit 0 ;;
            *)
                if [[ -z "$GITHUB_USER" ]]; then
                    GITHUB_USER="$1"
                else
                    echo "Unknown option: $1"
                    usage
                    exit 1
                fi
                ;;
        esac
        shift
    done

    if [[ -z "$GITHUB_USER" ]]; then
        echo "Error: GITHUB_USER is required"
        usage
        exit 1
    fi

    # Run installation steps
    $skip_shellcheck || install_shellcheck || handle_error $LINENO
    $skip_k3s || install_k3s || handle_error $LINENO
    $skip_flux || install_flux || handle_error $LINENO
    $skip_helm || install_helm || handle_error $LINENO
    $skip_sealed_secrets || install_sealed_secrets || handle_error $LINENO
    $skip_nginx || install_nginx_ingress || handle_error $LINENO
    $skip_kubeconform || install_kubeconform || handle_error $LINENO
    $skip_kubescore || install_kubescore || handle_error $LINENO

    log "All components installed successfully"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    trap cleanup EXIT
    main "${@:2}" 
fi