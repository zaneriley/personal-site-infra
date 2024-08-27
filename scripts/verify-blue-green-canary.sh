#!/bin/bash

# Default values
VERBOSITY=1
NAMESPACE="personal-site"
HOST="personal-site.local"
DRY_RUN=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Error tracking
ERRORS=0

# Timing
START_TIME=$(date +%s)

# Usage function
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Verify blue-green/canary deployment for personal site"
    echo
    echo "Options:"
    echo "  -h, --help              Show this help message"
    echo "  -n, --namespace NAME    Specify the Kubernetes namespace (default: personal-site)"
    echo "  -H, --host HOSTNAME     Specify the host to use in curl requests (default: personal-site.local)"
    echo "  -v, --verbose           Increase output verbosity"
    echo "  -d, --dry-run           Perform a dry run without making actual changes"
    echo
    echo "Verbosity levels:"
    echo "  1: Basic output (default)"
    echo "  2: Detailed output"
    echo "  3: Debug output"
}

# Logging function
log() {
    local level=$1
    shift
    if [[ $VERBOSITY -ge $level ]]; then
        echo -e "$@"
    fi
}

# Function to print headers
print_header() {
    log 1 "\n${BLUE}======== $1 ========${NC}"
}

# Function to show a spinner for long-running operations
spinner() {
    local pid=$1
    local delay=0.1
     # shellcheck disable=SC1003
    local spinstr='|/-\\'  
    while ps a | awk '{print $1}' | grep -q "$pid"; do  
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# Function to get the current backend service
get_current_backend() {
    kubectl get ingress personal-site -n "$NAMESPACE" -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.name}'
}

# Function to get the canary backend service
get_canary_backend() {
    kubectl get ingress personal-site-canary -n "$NAMESPACE" -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.name}'
}

# Function to test a specific deployment
test_deployment() {
    local deployment=$1
    local use_canary=$2
    local header=""
    
    if [ "$use_canary" = true ]; then
        header="-H 'X-Canary: true'"
    fi

    log 1 "\nTesting $deployment deployment..."
    if [ "$DRY_RUN" = true ]; then
        log 1 "${YELLOW}Dry run: Would test $deployment deployment${NC}"
        return
    fi

    local response
    response=$(curl -s -H "Host: $HOST" "$header" http://localhost)
    if [[ $response == *"$deployment"* ]]; then
        log 1 "${GREEN}Success: $deployment content detected${NC}"
    else
        log 1 "${RED}Failure: $deployment content not found${NC}"
        log 2 "Response: $response"
        ((ERRORS++))
    fi
    
    # Store test result
    TEST_RESULTS+=("$deployment:${response//$'\n'/ }")
}

# Function to switch deployment
switch_deployment() {
    log 1 "\n${BLUE}Switching deployment...${NC}"
    if [ "$DRY_RUN" = true ]; then
        log 1 "${YELLOW}Dry run: Would switch deployment${NC}"
        return
    fi

    if [ -f "./scripts/switch-deployment.sh" ]; then
        ./scripts/switch-deployment.sh &
        spinner $!
    else
        log 1 "${RED}Error: switch-deployment.sh not found${NC}"
        log 1 "Continuing with verification process..."
        ((ERRORS++))
    fi
}

# Function to calculate maximum widths for summary
calculate_max_widths() {
    local max_name_width=0

    for result in "${TEST_RESULTS[@]}"; do
        local deployment="${result%%:*}"
        local name_length=${#deployment}
        if (( name_length > max_name_width )); then
            max_name_width=$name_length
        fi
    done

    echo "$max_name_width"
}

# Function to format test results
format_test_result() {
    local deployment=$1
    local response=$2
    local max_name_width=$3
    local status_width=10  # Width for "Success" or "Failure"

    local status_symbol="✗"
    local status_text="Failure"
    local status_color=$RED

    if [[ $response == *"$deployment"* ]]; then
        status_symbol="✓"
        status_text="Success"
        status_color=$GREEN
    fi

    printf "${status_color}%s${NC} %-*s %-*s %s\n" \
        "$status_symbol" \
        "$max_name_width" "$deployment" \
        "$status_width" "$status_text" \
        "$response"
}

# Function to print summary
print_summary() {
    print_header "Verification Summary"

    local max_name_width
    max_name_width=$(calculate_max_widths)

    # Print header
    printf "${BLUE}%-*s %-10s %s${NC}\n" \
        "$((max_name_width + 2))" "Deployment" \
        "Status" \
        "Response"
    printf "${BLUE}%-*s %-10s %s${NC}\n" \
        "$((max_name_width + 2))" "----------" \
        "------" \
        "--------"

    for result in "${TEST_RESULTS[@]}"; do
        local deployment="${result%%:*}"
        local response="${result#*:}"
        format_test_result "$deployment" "$response" "$max_name_width"
    done

    # Print overall status
    local end_time
    end_time=$(date +%s)
    local duration
    duration=$((end_time - START_TIME))
    echo
    echo "Total duration: ${duration}s"
    echo "Total errors: ${ERRORS}"
    if [ "$ERRORS" -eq 0 ]; then
        echo -e "${GREEN}Overall status: SUCCESS${NC}"
    else
        echo -e "${RED}Overall status: FAILURE${NC}"
    fi
}

# Main function
main() {
    TEST_RESULTS=()

    print_header "Current State"
    local current_backend  
    current_backend=$(get_current_backend)  y
    local canary_backend  
    canary_backend=$(get_canary_backend)  y

    log 1 "Main backend: $current_backend"
    log 1 "Canary backend: $canary_backend"

    test_deployment "$current_backend" false
    test_deployment "$canary_backend" true

    switch_deployment

    print_header "New State"
    local new_current_backend  
    new_current_backend=$(get_current_backend)  y
    local new_canary_backend  
    new_canary_backend=$(get_canary_backend)  y

    log 1 "Main backend: $new_current_backend"
    log 1 "Canary backend: $new_canary_backend"

    test_deployment "$new_current_backend" false
    test_deployment "$new_canary_backend" true

    print_summary

    print_header "Verification Complete"
    log 1 "${GREEN}Verification process completed.${NC}"
}

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -H|--host)
            HOST="$2"
            shift 2
            ;;
        -v|--verbose)
            ((VERBOSITY++))
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Run the main function
main