#!/bin/bash

set -euo pipefail

# Define color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables for test results
SHELLCHECK_TOTAL=0
SHELLCHECK_PASSED=0
KUBECONFORM_TOTAL=0
KUBECONFORM_PASSED=0
KUBESCORE_TOTAL=0
KUBESCORE_PASSED=0

# Function to run ShellCheck on shell scripts
run_shellcheck() {
    echo -e "${BLUE}Running ShellCheck...${NC}"
    
    # Check if ShellCheck is installed
    if ! command -v shellcheck &> /dev/null; then
        echo -e "${RED}Error: ShellCheck is not installed or not in PATH${NC}"
        echo "Please install ShellCheck and try again."
        return 1
    fi
   
    local shell_scripts
    shell_scripts=$(find ./scripts -name "*.sh")

    # Debug: Print the list of scripts
    echo "Scripts to check: $shell_scripts"
    
    # Check if any script files were found
    if [ -z "$shell_scripts" ]; then
        echo -e "${YELLOW}Warning: No shell scripts found to check${NC}"
        return 0
    fi
    
    local shellcheck_failed=0
    
    # Debug: Enable command printing
    set -x
    
    for script in $shell_scripts; do
        echo "Processing script: $script"
        
        if [ ! -f "$script" ]; then
            echo -e "${YELLOW}Warning: Script file not found: $script${NC}"
            continue
        fi
        
        ((SHELLCHECK_TOTAL++))
        echo -e "${BLUE}Checking $script...${NC}"
        
        # Capture ShellCheck output
        shellcheck_output=$(shellcheck "$script" 2>&1) || true
        shellcheck_exit_code=$?
        
        echo "ShellCheck exit code: $shellcheck_exit_code"
        
        if [ $shellcheck_exit_code -eq 0 ]; then
            echo -e "${GREEN}✓ $script passed ShellCheck${NC}"
            ((SHELLCHECK_PASSED++))
        else
            echo -e "${RED}✗ $script failed ShellCheck${NC}"
            echo "$shellcheck_output"
            shellcheck_failed=1
        fi
    done
    
    # Debug: Disable command printing
    set +x
    
    if [ $shellcheck_failed -eq 1 ]; then
        echo -e "${YELLOW}Warning: Some scripts failed ShellCheck. Please review the output above.${NC}"
    fi
    
    return $shellcheck_failed
}

# Function to run Kubeconform on a file or directory
run_kubeconform() {
    local target="$1"
    echo -e "${BLUE}Running Kubeconform on $target...${NC}"
    ((KUBECONFORM_TOTAL++))
    if kubeconform -summary -output text -kubernetes-version 1.21.0 \
        -ignore-filename-pattern '\.github/.*' \
        -ignore-filename-pattern '\.release-please.*' \
        -ignore-filename-pattern '\.terraform/.*' \
        -ignore-filename-pattern 'kustomization\.yaml' \
        -ignore-filename-pattern 'kubeconfig\.yaml' \
        "$target"; then
        echo -e "${GREEN}✓ $target passed Kubeconform validation${NC}"
        ((KUBECONFORM_PASSED++))
    else
        echo -e "${RED}✗ $target failed Kubeconform validation${NC}"
    fi
}

# Function to run Kube-score on a file or directory
run_kubescore() {
    local target="$1"
    echo -e "${BLUE}Running Kube-score on $target...${NC}"
    ((KUBESCORE_TOTAL++))
    if [ -d "$target" ]; then
        # If target is a directory, find all yaml files and score them
        find "$target" -name "*.yaml" -type f | xargs kube-score score --output-format ci
    else
        # If target is a file, score it directly
        kube-score score "$target" --output-format ci
    fi
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ $target passed Kube-score checks${NC}"
        ((KUBESCORE_PASSED++))
    else
        echo -e "${YELLOW}! $target has Kube-score warnings${NC}"
    fi
}

# Function to print summary
print_summary() {
    echo -e "\n${BLUE}Test Summary:${NC}"
    echo -e "ShellCheck: ${GREEN}$SHELLCHECK_PASSED/$SHELLCHECK_TOTAL passed${NC}"
    echo -e "Kubeconform: ${GREEN}$KUBECONFORM_PASSED/$KUBECONFORM_TOTAL passed${NC}"
    echo -e "Kube-score: ${GREEN}$KUBESCORE_PASSED/$KUBESCORE_TOTAL passed${NC}"
    
    local total_passed=$((SHELLCHECK_PASSED + KUBECONFORM_PASSED + KUBESCORE_PASSED))
    local total_tests=$((SHELLCHECK_TOTAL + KUBECONFORM_TOTAL + KUBESCORE_TOTAL))
    
    if [ $total_passed -eq $total_tests ]; then
        echo -e "\n${GREEN}All tests passed successfully!${NC}"
    else
        echo -e "\n${RED}Some tests failed. Please review the output above.${NC}"
    fi
}

main() {
    local targets=("$@")

    if [ ${#targets[@]} -eq 0 ]; then
        targets=($(find . -name "*.yaml" -type f))
    fi

    # Run ShellCheck
    if ! run_shellcheck; then
        echo "ShellCheck failed. Continuing with other tests..."
    fi

    # Run Kubeconform and Kube-score
    for target in "${targets[@]}"; do
        if ! run_kubeconform "$target"; then
            echo "Kubeconform failed for $target. Continuing..."
        fi
        if ! run_kubescore "$target"; then
            echo "Kube-score failed for $target. Continuing..."
        fi
    done

    # Print summary
    print_summary

    # Set exit code
    local total_passed=$((SHELLCHECK_PASSED + KUBECONFORM_PASSED + KUBESCORE_PASSED))
    local total_tests=$((SHELLCHECK_TOTAL + KUBECONFORM_TOTAL + KUBESCORE_TOTAL))
    
    if [ $total_passed -eq $total_tests ]; then
        return 0
    else
        return 1
    fi
}

# Run the main function with all command-line arguments
main "$@"