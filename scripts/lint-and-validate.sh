#!/bin/bash

# set -euo pipefail
# set -x
# Define color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

PASS_SYMBOL='✓'
FAIL_SYMBOL='✗'
WARN_SYMBOL='!'

VERBOSITY=2 # 0: quiet, 1: normal, 2: verbose
SHELLCHECK_OUTPUT=""
KUBECONFORM_OUTPUT=""
KUBESCORE_OUTPUT=""

# Array to store test suite data
declare -A TEST_RESULTS

# Array to define order of test suites
test_suite_order=("ShellCheck" "Kubeconform" "Kube-score")

# Modify the existing log function or create a new one to handle different verbosity levels
log() {
    local level=$1
    shift
    if [[ $VERBOSITY -ge $level ]]; then
        echo -e "$@"
    fi
}

show_progress() {
    local current=$1
    local total=$2
    local test_suite=$3
    log 1 -ne "\r${BLUE}[$test_suite] Progress: $current/$total${NC}"
}

format_status() {
    local status=$1
    case "$status" in
        pass)
            echo -e "${GREEN}${PASS_SYMBOL} Passed${NC}"
            ;;
        fail)
            echo -e "${RED}${FAIL_SYMBOL} Failed${NC}"
            ;;
        warn)
            echo -e "${YELLOW}${WARN_SYMBOL} Warning${NC}"
            ;;
    esac
}

# Function to add test suite results
add_test_suite_results() {
    local name=$1
    TEST_RESULTS[$name,total]=$2
    TEST_RESULTS[$name,passed]=$3
    TEST_RESULTS[$name,failed]=$4
    TEST_RESULTS[$name,warnings]=${5:-0}
}

# Function to calculate maximum widths
calculate_max_widths() {
    local max_name_width=0
    local max_number_width=0

    for suite_key in "${!TEST_RESULTS[@]}"; do
        # Extract the suite name from the key (e.g., "ShellCheck,total" -> "ShellCheck")
        local suite_name="${suite_key%%,*}"
        local name_length=${#suite_name}
        if (( name_length > max_name_width )); then
            max_name_width=$name_length
        fi

        for metric in total passed failed warnings; do
            local metric_key="$suite_name,$metric"
            # Check if the key exists before trying to access its length
            if [[ -n "${TEST_RESULTS[$metric_key]}" ]]; then
                local number_length=${#TEST_RESULTS[$metric_key]}
                if (( number_length > max_number_width )); then
                    max_number_width=$number_length
                fi
            fi
        done
    done

    echo "$max_name_width $max_number_width"
}

# Function to format test results
format_test_results() {
    local suite=$1
    local max_name_width=$2
    local max_number_width=$3

    local total=${TEST_RESULTS[$suite,total]}
    local passed=${TEST_RESULTS[$suite,passed]}
    local failed=${TEST_RESULTS[$suite,failed]}
    local warnings=${TEST_RESULTS[$suite,warnings]}

    local status_symbol="✓"
    local status_color=$GREEN

    if (( failed > 0 )); then
        status_symbol="✗"
        status_color=$RED
    elif (( warnings > 0 )); then
        status_symbol="!"
        status_color=$YELLOW
    fi

    local passed_color=$NC
    local failed_color=$NC
    local warnings_color=$NC

    if (( passed > 0 )); then passed_color=$GREEN; fi
    if (( failed > 0 )); then failed_color=$RED; fi
    if (( warnings > 0 )); then warnings_color=$YELLOW; fi

    printf "${status_color}%s${NC} %-*s %*d total, ${passed_color}%d passed${NC}, ${failed_color}%d failed${NC}, ${warnings_color}%d warnings${NC}\n" \
        "$status_symbol" "$max_name_width" "$suite" "$max_number_width" "$total" "$passed" "$failed" "$warnings"
}

run_shellcheck() {
    local shell_scripts
    shell_scripts=$(find ./scripts -name "*.sh")
    local total_scripts
    total_scripts=$(echo "$shell_scripts" | wc -w)
    local current_script=0

    SHELLCHECK_TOTAL=$total_scripts
    SHELLCHECK_PASSED=0
    SHELLCHECK_FAILED=0
    SHELLCHECK_WARNINGS=0

   # Use an array to store output lines
    local output_lines=()
    local detailed_outputs=() 

    output_lines+=("Script                                   | Status   | Warnings  | Errors  | Notes")
    output_lines+=("--------------------------------------------------------------------------------")

    for script in $shell_scripts; do
        ((current_script++))
        local shellcheck_output
        shellcheck_output=$(shellcheck -f gcc "$script" 2>&1)
        local shellcheck_exit_code=$?
        local warning_count
        local error_count
        local note_count
        warning_count=$(echo "$shellcheck_output" | grep -c ": warning:")
        error_count=$(echo "$shellcheck_output" | grep -c ": error:")
        note_count=$(echo "$shellcheck_output" | grep -c ": note:")

        detailed_outputs+=("$script:\n$shellcheck_output\n")  # Store detailed output

        local status
        if [ $shellcheck_exit_code -ne 0 ]; then
            status=$(format_status fail)
            ((SHELLCHECK_FAILED++))
        else
            status=$(format_status pass)
            ((SHELLCHECK_PASSED++))
        fi
        output_lines+=("$(printf "%-40s | %s | %-9d | %-7d | %-5d" "$script" "$status" "$warning_count" "$error_count" "$note_count")")

    done
    output_lines+=("")

    # Join array elements with newlines
    SHELLCHECK_OUTPUT=$(printf '%s\n' "${output_lines[@]}")
}

run_kubeconform() {
    local files=("$@")
    local files_to_scan=("${files[@]}") # Create a mutable copy

    if [ ${#files_to_scan[@]} -eq 0 ]; then
        files_to_scan=(".")
    fi

    KUBECONFORM_OUTPUT="Running Kubeconform...\n"

    # Run Kubeconform on all files at once
    local output
    output=$(kubeconform -summary -verbose -output text -skip ImagePolicy,ImageUpdateAutomation,ImageRepository "${files_to_scan[@]}" 2>&1)

    # Process and align the output
    local aligned_output=""
    local max_file_length=0
    local max_resource_length=0

    # First pass to determine maximum lengths
    # Ensure lines are processed correctly even if they contain spaces
    while IFS= read -r line; do
        if [[ $line =~ ^[^[:space:]]+[[:space:]]-[[:space:]][^[:space:]]+[[:space:]][^[:space:]]+[[:space:]].*valid$ ]]; then
            local file_path
            file_path=$(echo "$line" | awk '{print $1}')
            local resource_type
            resource_type=$(echo "$line" | awk '{print $3}')
            
            [[ ${#file_path} -gt $max_file_length ]] && max_file_length=${#file_path}
            [[ ${#resource_type} -gt $max_resource_length ]] && max_resource_length=${#resource_type}
        fi
    done <<< "$output"

    # Second pass to format and align the output
    while IFS= read -r line; do
        if [[ $line =~ ^[^[:space:]]+[[:space:]]-[[:space:]][^[:space:]]+[[:space:]][^[:space:]]+[[:space:]].*valid$ ]]; then
            local file_path
            file_path=$(echo "$line" | awk '{print $1}')
            local resource_type
            resource_type=$(echo "$line" | awk '{print $3}')
            local resource_name
            resource_name=$(echo "$line" | awk '{print $4}')
            local status
            status=$(echo "$line" | awk '{$1=$2=$3=$4=""; print $0}' | sed 's/^[ \t]*//') # Get the rest of the line as status
            
            printf -v aligned_line "%-*s - %-*s %-30s %s\n" "$max_file_length" "$file_path" "$max_resource_length" "$resource_type" "$resource_name" "$status"
            aligned_output+="$aligned_line"
        elif [[ $line =~ ^Summary: ]]; then
            aligned_output+="\n$line\n"
        fi
    done <<< "$output"

    KUBECONFORM_OUTPUT+="$aligned_output\n"

    # Extract summary line
    local summary
    summary=$(echo "$output" | tail -n 1)
       
    # Parse summary
    if [[ $summary =~ ([0-9]+)[[:space:]]resources[[:space:]]found[[:space:]]in[[:space:]]([0-9]+)[[:space:]]files[[:space:]]-[[:space:]]Valid:[[:space:]]([0-9]+),[[:space:]]Invalid:[[:space:]]([0-9]+),[[:space:]]Errors:[[:space:]]([0-9]+),[[:space:]]Skipped:[[:space:]]([0-9]+) ]]; then
        local total_resources="${BASH_REMATCH[1]}"
        # local total_files="${BASH_REMATCH[2]}" # unused variable
        local valid_resources="${BASH_REMATCH[3]}"
        local invalid_resources="${BASH_REMATCH[4]}"
        local error_resources="${BASH_REMATCH[5]}"

        KUBECONFORM_TOTAL=$total_resources
        KUBECONFORM_PASSED=$valid_resources
        KUBECONFORM_FAILED=$((invalid_resources + error_resources))
    else
        KUBECONFORM_OUTPUT+="Failed to parse Kubeconform summary.\n"
        KUBECONFORM_TOTAL=0
        KUBECONFORM_PASSED=0
        KUBECONFORM_FAILED=0
        log 2 "DEBUG: Regex did not match Kubeconform summary: $summary"
    fi
}

colorize_kubescore_output() {
    local line="$1"
    if [[ $line == *"[CRITICAL]"* ]]; then
        echo -e "${RED}${line}${NC}"
    elif [[ $line == *"[WARN]"* ]]; then # Also colorize warnings
        echo -e "${YELLOW}${line}${NC}"
    else
        echo "$line"
    fi
}
# Modify run_kubescore function
run_kubescore() {
    local files_to_scan=("$@") # Use a different name to avoid confusion
    local total_files_to_scan=${#files_to_scan[@]}
    local validated_files=0

    # Initialize counts at the beginning of the function
    KUBESCORE_TOTAL=0
    KUBESCORE_PASSED=0
    KUBESCORE_FAILED=0
    KUBESCORE_WARNINGS=0

    KUBESCORE_OUTPUT="Running Kube-score on $total_files_to_scan file(s)...\n"

    for file in "${files_to_scan[@]}"; do
        ((validated_files++))
        show_progress "$validated_files" "$total_files_to_scan" "Kube-score"

        local output
        output=$(kube-score score --ignore-test pod-probes "$file" 2>&1)

        local critical_count
        critical_count=$(echo "$output" | grep -c "\[CRITICAL\]")
        local warning_count
        warning_count=$(echo "$output" | grep -c "\[WARN\]")

        ((KUBESCORE_TOTAL++)) # Increment total for each file processed

        if [ "$critical_count" -eq 0 ] && [ "$warning_count" -eq 0 ]; then
            ((KUBESCORE_PASSED++))
            KUBESCORE_OUTPUT+="✓ $file passed Kube-score\n"
        elif [ "$critical_count" -eq 0 ]; then
            # Only warnings, not a failure for the summary, but increment warnings
            KUBESCORE_OUTPUT+="! $file has Kube-score warnings\n"
             ((KUBESCORE_WARNINGS += warning_count)) # Add to existing warnings
        else
            ((KUBESCORE_FAILED++))
            KUBESCORE_OUTPUT+="✗ $file failed Kube-score\n"
            # If there are critical errors, still count warnings for detailed output
            ((KUBESCORE_WARNINGS += warning_count))
        fi

        # Detailed output based on verbosity
        if [ "$VERBOSITY" -ge 2 ]; then
            while IFS= read -r line; do
                KUBESCORE_OUTPUT+="$(colorize_kubescore_output "$line")\n"
            done <<< "$output"
        elif [ "$VERBOSITY" -ge 1 ]; then
             # Only show lines with CRITICAL or WARN for normal verbosity
            while IFS= read -r line; do
                if [[ "$line" =~ \[CRITICAL\]|\[WARN\] ]]; then
                    KUBESCORE_OUTPUT+="$(colorize_kubescore_output "$line")\n"
                fi
            done <<< "$output"
        fi
    done
    # Ensure progress indicator is cleared
    log 1 ""
}

# Function to print test results
print_test_results() {
    log 1 "\n${BLUE}======== ShellCheck Results ========${NC}"
    echo -e "$SHELLCHECK_OUTPUT"
    log 1 "${BLUE}ShellCheck Summary:${NC}"
    log 1 "Total: $SHELLCHECK_TOTAL, Passed: $SHELLCHECK_PASSED, Failed: $SHELLCHECK_FAILED, Warnings: $SHELLCHECK_WARNINGS\n"

    log 1 "\n${BLUE}======== Kubeconform Results ========${NC}"
    echo -e "$KUBECONFORM_OUTPUT"
    log 1 "${BLUE}Kubeconform Summary:${NC}"
    log 1 "Total: $KUBECONFORM_TOTAL, Passed: $KUBECONFORM_PASSED, Failed: $KUBECONFORM_FAILED\n"

    log 1 "\n${BLUE}======== Kube-score Results ========${NC}"
    echo -e "$KUBESCORE_OUTPUT"
    log 1 "${BLUE}Kube-score Summary:${NC}"
    log 1 "Total: $KUBESCORE_TOTAL, Passed: $KUBESCORE_PASSED, Failed: $KUBESCORE_FAILED, Warnings: $KUBESCORE_WARNINGS\n"
}

print_summary() {
    log 1 "\n${BLUE}Test Summary:${NC}"

    add_test_suite_results "ShellCheck" "$SHELLCHECK_TOTAL" "$SHELLCHECK_PASSED" "$SHELLCHECK_FAILED" "$SHELLCHECK_WARNINGS"
    add_test_suite_results "Kubeconform" "$KUBECONFORM_TOTAL" "$KUBECONFORM_PASSED" "$KUBECONFORM_FAILED" "0" # Kubeconform doesn't have warnings in this script's context
    add_test_suite_results "Kube-score" "$KUBESCORE_TOTAL" "$KUBESCORE_PASSED" "$KUBESCORE_FAILED" "$KUBESCORE_WARNINGS"

    read -r max_name_width max_number_width < <(calculate_max_widths)

    for suite in "${test_suite_order[@]}"; do
        format_test_results "$suite" "$max_name_width" "$max_number_width"
    done
}



main() {
    # Check for required tools
    local missing_tools=false
    if ! command -v shellcheck &> /dev/null; then
        log 1 "${RED}ShellCheck is not installed. Please install it to continue.${NC}"
        log 1 "Installation instructions: https://github.com/koalaman/shellcheck#installing"
        missing_tools=true
    fi
    if ! command -v kubeconform &> /dev/null; then
        log 1 "${RED}Kubeconform is not installed. Please install it to continue.${NC}"
        log 1 "Installation instructions: https://github.com/yannh/kubeconform#installation"
        missing_tools=true
    fi
    if ! command -v kube-score &> /dev/null; then
        log 1 "${RED}Kube-score is not installed. Please install it to continue.${NC}"
        log 1 "Installation instructions: https://github.com/zegl/kube-score#installation"
        missing_tools=true
    fi

    if [ "$missing_tools" = true ]; then
        exit 1
    fi

    local targets_args=("$@")
    local k8s_files_to_scan=()

    if [ ${#targets_args[@]} -eq 0 ]; then
        # Find all .yaml files if no specific targets are given
        mapfile -t k8s_files_to_scan < <(find . -name "*.yaml" -type f)
    else
        # Process provided arguments: if it's a directory, find yaml files in it, otherwise assume it's a file
        for arg in "${targets_args[@]}"; do
            if [ -d "$arg" ]; then
                mapfile -t found_files < <(find "$arg" -name "*.yaml" -type f)
                for ff in "${found_files[@]}"; do
                     k8s_files_to_scan+=("$ff")
                done
            elif [ -f "$arg" ]; then
                k8s_files_to_scan+=("$arg")
            else
                log 1 "${YELLOW}Warning: Argument '$arg' is not a valid file or directory. Skipping.${NC}"
            fi
        done
    fi

    run_shellcheck # Runs on all scripts in ./scripts/

    # Filter out ignored files for k8s scans
    local filtered_k8s_files=()
    for target_file in "${k8s_files_to_scan[@]}"; do
        if [[ ! "$target_file" =~ \.github/|\.release-please|\.terraform/|kustomization\.yaml|kubeconfig\.yaml ]]; then
            filtered_k8s_files+=("$target_file")
        else
            log 1 "${YELLOW}Skipping K8s scan for ignored file: $target_file${NC}"
        fi
    done

    # Run Kubeconform and Kube-score on filtered k8s files
    if [ ${#filtered_k8s_files[@]} -gt 0 ]; then
      run_kubeconform "${filtered_k8s_files[@]}"
      run_kubescore "${filtered_k8s_files[@]}"
    else
      log 1 "${YELLOW}No Kubernetes files to scan after filtering.${NC}"
      # Initialize Kubeconform and Kube-score results as empty/passed if no files
      KUBECONFORM_TOTAL=0 KUBECONFORM_PASSED=0 KUBECONFORM_FAILED=0
      KUBESCORE_TOTAL=0 KUBESCORE_PASSED=0 KUBESCORE_FAILED=0 KUBESCORE_WARNINGS=0
    fi


    # Print test results
    print_test_results
    print_summary

    # Determine overall test status
    local total_failed=$(( ${SHELLCHECK_FAILED:-0} + ${KUBECONFORM_FAILED:-0} + ${KUBESCORE_FAILED:-0} ))
    local total_warnings=$(( ${SHELLCHECK_WARNINGS:-0} + ${KUBESCORE_WARNINGS:-0} )) # Kubeconform warnings are not explicitly tracked here

    if (( total_failed == 0 && total_warnings == 0 )); then
        log 1 "${GREEN}All tests passed successfully!${NC}"
        exit 0
    elif (( total_failed == 0 )); then
        log 1 "${YELLOW}All tests passed, but there are warnings. Please review the output above.${NC}"
        exit 0 # Still exit 0 if only warnings
    else
        log 1 "${RED}Some tests failed. Please review the output above.${NC}"
        exit 1
    fi
}


# Run the main function with all command-line arguments
main "$@"