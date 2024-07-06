#!/bin/bash

# set -euo pipefail

# Define color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables for test results
SHELLCHECK_TOTAL=0
SHELLCHECK_PASSED=0
SHELLCHECK_FAILED=0
SHELLCHECK_WARNINGS=0

KUBECONFORM_TOTAL=0
KUBECONFORM_PASSED=0
KUBECONFORM_FAILED=0

KUBESCORE_TOTAL=0
KUBESCORE_PASSED=0
KUBESCORE_FAILED=0
KUBESCORE_WARNINGS=0

# Array to store test suite data
declare -A test_suites


# Array to define order of test suites
test_suite_order=("ShellCheck" "Kubeconform" "Kube-score")

# Function to add test suite results
add_test_suite_results() {
    local name=$1
    test_suites[$name,total]=$2
    test_suites[$name,passed]=$3
    test_suites[$name,failed]=$4
    test_suites[$name,warnings]=${5:-0}
}

# Function to calculate maximum widths
calculate_max_widths() {
    local max_name_width=0
    local max_number_width=0

    for suite in "${!test_suites[@]}"; do
        local name_length=${#suite}
        if (( name_length > max_name_width )); then
            max_name_width=$name_length
        fi

        for metric in total passed failed warnings; do
            local number_length=${#test_suites[$suite,$metric]}
            if (( number_length > max_number_width )); then
                max_number_width=$number_length
            fi
        done
    done

    echo "$max_name_width $max_number_width"
}

# Function to format a line with color
format_color_line() {
    local color=$1
    local text=$2
    echo -e "${color}${text}${NC}"
}

# Function to apply color to a metric
apply_color() {
    local value=$1
    local color=$2
    local label=$3
    local width=$4
    if (( value == 0 )); then
        printf "%*d %s" "$width" "$value" "$label"
    else
        printf "${color}%*d %s${NC}" "$width" "$value" "$label"
    fi
}

# Function to format test results
format_test_results() {
    local suite=$1
    local max_name_width=$2
    local max_number_width=$3

    local total=${test_suites[$suite,total]}
    local passed=${test_suites[$suite,passed]}
    local failed=${test_suites[$suite,failed]}
    local warnings=${test_suites[$suite,warnings]}

    local status_symbol="✓"
    local status_color=$GREEN

    if (( failed > 0 )); then
        status_symbol="✗"
        status_color=$RED
    elif (( warnings > 0 )); then
        status_symbol="!"
        status_color=$YELLOW
    fi

    local total_str=$(apply_color $total $BLUE "total" $max_number_width)
    local passed_str=$(apply_color $passed $GREEN "passed" $max_number_width)
    local failed_str=$(apply_color $failed $RED "failed" $max_number_width)
    local warnings_str=$(apply_color $warnings $YELLOW "warnings" $max_number_width)

    echo -e "${status_color}${status_symbol}${NC} $(printf "%-*s" $max_name_width "$suite") $total_str, $passed_str, $failed_str, $warnings_str"
}

# Function to run ShellCheck on shell scripts
run_shellcheck() {
    echo -e "${BLUE}Running ShellCheck...${NC}"

    SHELLCHECK_TOTAL=0
    SHELLCHECK_PASSED=0
    SHELLCHECK_FAILED=0
    SHELLCHECK_WARNINGS=0
    
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
        
                shellcheck_output=$(shellcheck "$script" 2>&1) || true
        shellcheck_exit_code=$?
        
        if [ $shellcheck_exit_code -eq 0 ]; then
            echo -e "${GREEN}✓ $script passed ShellCheck${NC}"
            ((SHELLCHECK_PASSED++))
        elif [ $shellcheck_exit_code -eq 1 ]; then
            echo -e "${YELLOW}! $script has ShellCheck warnings${NC}"
            ((SHELLCHECK_WARNINGS++))
        else
            echo -e "${RED}✗ $script failed ShellCheck${NC}"
            shellcheck_failed=1
        fi
        echo "$shellcheck_output"
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
        ((KUBECONFORM_FAILED++))
    fi
}

# Function to run Kube-score on a file or directory
run_kubescore() {
    local target="$1"
    echo -e "${BLUE}Running Kube-score on $target...${NC}"
    ((KUBESCORE_TOTAL++))
    
    local kubescore_output
    if [ -d "$target" ]; then
        kubescore_output=$(find "$target" -name "*.yaml" -type f | xargs kube-score score --output-format ci 2>&1)
    else
        kubescore_output=$(kube-score score "$target" --output-format ci 2>&1)
    fi
    local kubescore_exit_code=$?
    
    echo "$kubescore_output"
    
    if [ $kubescore_exit_code -eq 0 ]; then
        echo -e "${GREEN}✓ $target passed Kube-score checks${NC}"
        ((KUBESCORE_PASSED++))
    elif echo "$kubescore_output" | grep -q "\[CRITICAL\]"; then
        echo -e "${RED}✗ $target has Kube-score critical issues${NC}"
        ((KUBESCORE_FAILED++))
    else
        echo -e "${YELLOW}! $target has Kube-score warnings${NC}"
        ((KUBESCORE_WARNINGS++))
    fi
}

# Update print_summary function
print_summary() {
    echo -e "\n${BLUE}Test Summary:${NC}"

    add_test_suite_results "ShellCheck" $SHELLCHECK_TOTAL $SHELLCHECK_PASSED $SHELLCHECK_FAILED $SHELLCHECK_WARNINGS
    add_test_suite_results "Kubeconform" $KUBECONFORM_TOTAL $KUBECONFORM_PASSED $KUBECONFORM_FAILED 0
    add_test_suite_results "Kube-score" $KUBESCORE_TOTAL $KUBESCORE_PASSED $KUBESCORE_FAILED $KUBESCORE_WARNINGS

    read max_name_width max_number_width <<< $(calculate_max_widths)

    for suite in "${test_suite_order[@]}"; do
        format_test_results "$suite" "$max_name_width" "$max_number_width"
    done

    local total_failed=$((SHELLCHECK_FAILED + KUBECONFORM_FAILED + KUBESCORE_FAILED))
    local total_warnings=$((SHELLCHECK_WARNINGS + KUBESCORE_WARNINGS))

    if (( total_failed == 0 && total_warnings == 0 )); then
        format_color_line $GREEN "\nAll tests passed successfully!"
    elif (( total_failed == 0 )); then
        format_color_line $YELLOW "\nAll tests passed, but there are warnings. Please review the output above."
    else
        format_color_line $RED "\nSome tests failed. Please review the output above."
    fi
}


# Update the main function
main() {
    local targets=("$@")

    if [ ${#targets[@]} -eq 0 ]; then
        targets=($(find . -name "*.yaml" -type f))
    fi

    local tests_run=false

    # Run ShellCheck
    if ! run_shellcheck; then
        echo "ShellCheck failed. Continuing with other tests..."
    fi

    # Run Kubeconform and Kube-score
    for target in "${targets[@]}"; do
        if [[ "$target" =~ \.github/|\.release-please|\.terraform/|kustomization\.yaml|kubeconfig\.yaml ]]; then
            echo -e "${YELLOW}Skipping ignored file: $target${NC}"
            continue
        fi
        run_kubeconform "$target"
        run_kubescore "$target"
    done

    # Print summary
    print_summary

    # Set exit code
    if [ ${KUBECONFORM_FAILED:-0} -gt 0 ] || [ ${KUBESCORE_FAILED:-0} -gt 0 ] || [ $SHELLCHECK_FAILED -gt 0 ]; then
        return 1
    elif [ ${KUBESCORE_WARNINGS:-0} -gt 0 ] || [ ${SHELLCHECK_WARNINGS:-0} -gt 0 ]; then
        return 2
    else
        return 0
    fi
}

# Run the main function with all command-line arguments
main "$@"