#!/bin/bash

# set -euo pipefail
# set -x
# Define color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

VERBOSITY=2 # 0: quiet, 1: normal, 2: verbose
SHELLCHECK_OUTPUT=""
KUBECONFORM_OUTPUT=""
KUBESCORE_OUTPUT=""

# Array to store test suite data
declare -A TEST_RESULTS

# Array to define order of test suites
test_suite_order=("ShellCheck" "Kubeconform" "Kube-score")


# Utility functions
log() {
    local level=$1
    shift
    if [[ $VERBOSITY -ge $level ]]; then
        echo -e "$@"
    fi
}
print_header() {
    log 1 "\n${BLUE}======== $1 ========${NC}"
}

print_section_break() {
    log 1 "\n${BLUE}----------------------------------------${NC}"
}
print_suite_summary() {
    local suite=$1
    local total=$2
    local passed=$3
    local failed=$4
    local warnings=${5:-0}
    
    local status_symbol="✓"
    local status_color=$GREEN
    
    if (( failed > 0 )); then
        status_symbol="✗"
        status_color=$RED
    elif (( warnings > 0 )); then
        status_symbol="!"
        status_color=$YELLOW
    fi
    
    log 1 "\n${status_color}${status_symbol}${NC} ${BLUE}${suite} Summary:${NC}"
    log 1 "  Total: $total, Passed: $passed, Failed: $failed, Warnings: $warnings"
}

time_command() {
    local start_time
    local end_time
    local duration

    start_time=$(date +%s.%N)
    "$@"
    end_time=$(date +%s.%N)
    duration=$(echo "$end_time - $start_time" | bc)
    log 2 "${YELLOW}Execution time: ${duration} seconds${NC}"
}

show_progress() {
    local current=$1
    local total=$2
    local test_suite=$3
    log 1 -ne "\r${BLUE}[$test_suite] Progress: $current/$total${NC}"
}

format_error() {
    local severity=$1
    local message=$2
    case $severity in
        "warning") log 1 "${YELLOW}WARNING: $message${NC}" ;;
        "error") log 1 "${RED}ERROR: $message${NC}" ;;
        *) log 1 "$message" ;;
    esac
}

prompt_for_fix() {
    local script=$1
    read -p "Do you want to fix issues in ""$script"" now? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        $EDITOR "$script"
    fi
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

    for suite in "${!TEST_RESULTS[@]}"; do
        local name_length=${#suite}
        if (( name_length > max_name_width )); then
            max_name_width=$name_length
        fi

        for metric in total passed failed warnings; do
            local number_length=${#TEST_RESULTS[$suite,$metric]}
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

debug_print() {
    if [[ $VERBOSITY -ge 2 ]]; then
        echo "DEBUG: $*" >&2
    fi
}

run_shellcheck() {
    local shell_scripts
    shell_scripts=$(find ./scripts -name "*.sh")
    local total_scripts
    total_scripts=$(echo "$shell_scripts" | wc -w)
    local current_script=0

    SHELLCHECK_TOTAL=$total_scripts
    SHELLCHECK_PASSED=0
    SHELLCHECK_FIXED=0
    SHELLCHECK_FAILED=0
    SHELLCHECK_WARNINGS=0
    SHELLCHECK_INFO=0

    SHELLCHECK_OUTPUT+="Checking $total_scripts script(s)\n"

    for script in $shell_scripts; do
        ((current_script++))
        show_progress "$current_script" "$total_scripts" "ShellCheck"

        local shellcheck_output
        shellcheck_output=$(shellcheck -f gcc "$script" 2>&1)
        local shellcheck_exit_code=$?

        local warning_count
        local info_count
        warning_count=$(echo "$shellcheck_output" | grep -c ": warning:")
        info_count=$(echo "$shellcheck_output" | grep -c ": note:")

        if [ $shellcheck_exit_code -eq 0 ] && [ "$warning_count" -eq 0 ] && [ "$info_count" -eq 0 ]; then
            ((SHELLCHECK_PASSED++))
            SHELLCHECK_OUTPUT+="✓ $script passed ShellCheck\n"
        else
            # Generate diff and apply fixes
            local diff_output
            diff_output=$(shellcheck -f diff "$script")
            if [ -n "$diff_output" ]; then
                echo "$diff_output" | patch -p1 "$script"
                ((SHELLCHECK_FIXED++))
                SHELLCHECK_OUTPUT+="✓ $script fixed by ShellCheck\n"
            else
                ((SHELLCHECK_FAILED++))
                SHELLCHECK_OUTPUT+="✗ $script failed ShellCheck and couldn't be automatically fixed\n"
                SHELLCHECK_OUTPUT+="$shellcheck_output\n"
            fi
        fi

        ((SHELLCHECK_WARNINGS += warning_count))
        ((SHELLCHECK_INFO += info_count))
    done
    
    echo # New line after progress bar
}


run_kubeconform() {
    local files=("$@")
    
    if [ ${#files[@]} -eq 0 ]; then
        files=(".")
    fi

    KUBECONFORM_OUTPUT="Running Kubeconform...\n"

    # Run Kubeconform on all files at once
    local output
    output=$(kubeconform -summary -verbose -output text "${files[@]}" 2>&1)

    # Process and align the output
    local aligned_output=""
    local max_file_length=0
    local max_resource_length=0

    # First pass to determine maximum lengths
    while IFS= read -r line; do
        if [[ $line =~ ^./.*valid$ ]]; then
            local file_path
            file_path=$(echo "$line" | cut -d' ' -f1)
            local resource_type
            resource_type=$(echo "$line" | cut -d' ' -f3)
            local resource_name
            resource_name=$(echo "$line" | cut -d' ' -f4)
            
            [[ ${#file_path} -gt $max_file_length ]] && max_file_length=${#file_path}
            [[ ${#resource_type} -gt $max_resource_length ]] && max_resource_length=${#resource_type}
        fi
    done <<< "$output"

    # Second pass to format and align the output
    while IFS= read -r line; do
        if [[ $line =~ ^./.*valid$ ]]; then
            local file_path
            file_path=$(echo "$line" | cut -d' ' -f1)
            local resource_type
            resource_type=$(echo "$line" | cut -d' ' -f3)
            local resource_name
            resource_name=$(echo "$line" | cut -d' ' -f4)
            local status
            status=$(echo "$line" | cut -d' ' -f6-)
            
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
        local total_files="${BASH_REMATCH[2]}"
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
        echo "DEBUG: Regex did not match"
    fi
}

# Modify run_kubescore function
run_kubescore() {
    local files=("$@")
    local total_files=${#files[@]}
    local validated_files=0

    KUBESCORE_TOTAL=$total_files
    KUBESCORE_PASSED=0
    KUBESCORE_FAILED=0
    KUBESCORE_WARNINGS=0

    KUBESCORE_OUTPUT="Running Kube-score on $total_files file(s)...\n"

    for file in "${files[@]}"; do
        ((validated_files++))
        show_progress "$validated_files" "$total_files" "Kube-score"

        local output
        output=$(kube-score score --ignore-test pod-probes "$file" 2>&1)


        local critical_count
        critical_count=$(echo "$output" | grep -c "\[CRITICAL\]")
        local warning_count
        warning_count=$(echo "$output" | grep -c "\[WARN\]")

        ((KUBESCORE_TOTAL++))

        if [ "$critical_count" -eq 0 ] && [ "$warning_count" -eq 0 ]; then
            ((KUBESCORE_PASSED++))
            KUBESCORE_OUTPUT+="✓ $file passed Kube-score\n"
        elif [ "$critical_count" -eq 0 ]; then
            ((KUBESCORE_WARNINGS++))
            KUBESCORE_OUTPUT+="! $file has Kube-score warnings\n"
        else
            ((KUBESCORE_FAILED++))
            KUBESCORE_OUTPUT+="✗ $file failed Kube-score\n"
        fi

        if [ "$VERBOSITY" -ge 2 ]; then
            KUBESCORE_OUTPUT+="$output\n"
        elif [ "$VERBOSITY" -ge 1 ]; then
            KUBESCORE_OUTPUT+="$(echo "$output" | grep -E "\[CRITICAL\]|\[WARN\]")\n"
        fi

        ((KUBESCORE_WARNINGS += warning_count))
    done

    echo # New line after progress bar
    KUBESCORE_OUTPUT+="\n[Kube-score] Summary: $KUBESCORE_TOTAL total, $KUBESCORE_PASSED passed, $KUBESCORE_FAILED failed, $KUBESCORE_WARNINGS warnings\n"
}

# Function to print test results
print_test_results() {
    print_header "ShellCheck Results"
    echo -e "$SHELLCHECK_OUTPUT"
    echo -e "${BLUE}ShellCheck Summary:${NC}"
    echo -e "Total: $SHELLCHECK_TOTAL, Passed: $SHELLCHECK_PASSED, Failed: $SHELLCHECK_FAILED, Warnings: $SHELLCHECK_WARNINGS\n"

    print_header "Kubeconform Results"
    echo -e "$KUBECONFORM_OUTPUT"
    echo -e "${BLUE}Kubeconform Summary:${NC}"
    echo -e "Total: $KUBECONFORM_TOTAL, Passed: $KUBECONFORM_PASSED, Failed: $KUBECONFORM_FAILED\n"

    print_header "Kube-score Results"
    echo -e "$KUBESCORE_OUTPUT"
    echo -e "${BLUE}Kube-score Summary:${NC}"
    echo -e "Total: $KUBESCORE_TOTAL, Passed: $KUBESCORE_PASSED, Failed: $KUBESCORE_FAILED, Warnings: $KUBESCORE_WARNINGS\n"
}

print_summary() {
    echo -e "\n${BLUE}Test Summary:${NC}"

    add_test_suite_results "ShellCheck" "$SHELLCHECK_TOTAL" "$SHELLCHECK_PASSED" "$SHELLCHECK_FAILED" $SHELLCHECK_WARNINGS
    add_test_suite_results "Kubeconform" $KUBECONFORM_TOTAL $KUBECONFORM_PASSED $KUBECONFORM_FAILED 0
    add_test_suite_results "Kube-score" "$KUBESCORE_TOTAL" "$KUBESCORE_PASSED" "$KUBESCORE_FAILED" $KUBESCORE_WARNINGS

    read -r max_name_width max_number_width < <(calculate_max_widths)

    for suite in "${test_suite_order[@]}"; do
        format_test_results "$suite" "$max_name_width" "$max_number_width"
    done
}



main() {

    local targets=("$@")

    if [ ${#targets[@]} -eq 0 ]; then
        mapfile -t targets < <(find . -name "*.yaml" -type f)
    fi

    run_shellcheck

    # Filter out ignored files
    local filtered_targets=()
    for target in "${targets[@]}"; do
        if [[ ! "$target" =~ \.github/|\.release-please|\.terraform/|kustomization\.yaml|kubeconfig\.yaml ]]; then
            filtered_targets+=("$target")
        else
            echo -e "${YELLOW}Skipping ignored file: $target${NC}"
        fi
    done

    # Run Kubeconform and Kube-score on filtered targets
    run_kubeconform "${filtered_targets[@]}"
    run_kubescore "${filtered_targets[@]}"

    # Print test results
    print_test_results
    print_summary

    # Determine overall test status
    local total_failed=$((SHELLCHECK_FAILED + KUBECONFORM_FAILED + KUBESCORE_FAILED))
    local total_warnings=$((SHELLCHECK_WARNINGS + KUBESCORE_WARNINGS))

    if (( total_failed == 0 && total_warnings == 0 )); then
        echo -e "${GREEN}All tests passed successfully!${NC}"
        exit 0
    elif (( total_failed == 0 )); then
        echo -e "${YELLOW}All tests passed, but there are warnings. Please review the output above.${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed. Please review the output above.${NC}"
        exit 1
    fi
}


# Run the main function with all command-line arguments
main "$@"