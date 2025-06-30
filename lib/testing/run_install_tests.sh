#!/usr/bin/env bash
#
# Run install script tests from various locations
# Checks for test files and executes them
#

set -euo pipefail

if [[ -f "tests/test_install.sh" ]]; then
    echo "Running install script tests..."
    ./tests/test_install.sh
elif [[ -d "lib/install/tests" ]]; then
    echo "Running tests in lib/install/tests..."
    for test in lib/install/tests/*.sh; do
        if [[ -f "$test" ]]; then
            echo "Running $test..."
            bash "$test"
        fi
    done
else
    echo "No install tests found."
    echo "Create tests/test_install.sh or tests in lib/install/tests/"
fi