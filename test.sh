#!/usr/bin/env bash

# Test runner script for dotfiles repository
# Provides convenient ways to run tests with different configurations

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[test]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[test]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[test]${NC} $*"
}

log_error() {
    echo -e "${RED}[test]${NC} $*" >&2
}

# Show help
show_help() {
    cat << EOF
Test Runner for Dotfiles Repository

USAGE:
    $0 [COMMAND] [OPTIONS]

COMMANDS:
    unit            Run unit tests only (default)
    integration     Run integration tests only  
    all             Run all tests
    coverage        Run tests with coverage report
    fast            Run tests in parallel (fast)
    package         Run package analysis tests only
    actions         Run GitHub Actions tests with act (local only)
    lint            Run code quality checks (ruff, black, mypy)
    format          Format code with black and ruff
    clean           Clean test artifacts and cache

OPTIONS:
    -v, --verbose   Verbose output
    -q, --quiet     Quiet output (errors only)
    -f, --failfast  Stop on first failure
    --no-cov        Skip coverage reporting

EXAMPLES:
    $0                  # Run unit tests
    $0 all              # Run all tests
    $0 coverage         # Run with coverage
    $0 fast -v          # Run in parallel with verbose output
    $0 package          # Test package analysis only
    $0 actions          # Test GitHub Actions with act
    $0 lint             # Check code quality
    $0 format           # Format code

PYTEST ARGUMENTS:
    Any unrecognized arguments are passed directly to pytest:
    $0 unit tests/test_package_analysis.py::TestRepologyClientMocking -v

For more information about pytest options: pytest --help
EOF
}

# Default values
COMMAND="unit"
VERBOSE=""
QUIET=""
FAILFAST=""
NO_COV=""
PYTEST_ARGS=()

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        unit|integration|all|coverage|fast|package|actions|lint|format|clean)
            COMMAND="$1"
            shift
            ;;
        -v|--verbose)
            VERBOSE="-v"
            shift
            ;;
        -q|--quiet)
            QUIET="-q"
            shift
            ;;
        -f|--failfast)
            FAILFAST="-x"
            shift
            ;;
        --no-cov)
            NO_COV="true"
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            # Pass unknown arguments to pytest
            PYTEST_ARGS+=("$1")
            shift
            ;;
    esac
done

# Build pytest command
build_pytest_cmd() {
    local cmd="uv run pytest"
    
    # Add verbosity
    if [[ -n "$VERBOSE" ]]; then
        cmd="$cmd $VERBOSE"
    elif [[ -n "$QUIET" ]]; then
        cmd="$cmd $QUIET"
    fi
    
    # Add fail fast
    if [[ -n "$FAILFAST" ]]; then
        cmd="$cmd $FAILFAST"
    fi
    
    # Add coverage unless disabled
    if [[ -z "$NO_COV" && "$COMMAND" != "lint" && "$COMMAND" != "format" && "$COMMAND" != "clean" ]]; then
        cmd="$cmd --cov=bin --cov=lib --cov-report=term-missing"
    fi
    
    echo "$cmd"
}

# Run unit tests
run_unit_tests() {
    log_info "Running unit tests..."
    local cmd
    cmd=$(build_pytest_cmd)
    $cmd -m "not integration" "${PYTEST_ARGS[@]+"${PYTEST_ARGS[@]+"${PYTEST_ARGS[@]}"}"}"
}

# Run integration tests
run_integration_tests() {
    log_info "Running integration tests..."
    local cmd
    cmd=$(build_pytest_cmd)
    $cmd -m "integration" "${PYTEST_ARGS[@]+"${PYTEST_ARGS[@]}"}"
}

# Run all tests
run_all_tests() {
    log_info "Running all tests..."
    local cmd
    cmd=$(build_pytest_cmd)
    $cmd "${PYTEST_ARGS[@]+"${PYTEST_ARGS[@]}"}"
}

# Run tests with coverage
run_coverage_tests() {
    log_info "Running tests with detailed coverage..."
    uv run pytest --cov=bin --cov=lib \
           --cov-report=term-missing \
           --cov-report=html:htmlcov \
           --cov-report=xml \
           $VERBOSE $QUIET $FAILFAST \
           "${PYTEST_ARGS[@]+"${PYTEST_ARGS[@]}"}"
    
    log_success "Coverage report generated:"
    echo "  HTML: htmlcov/index.html"
    echo "  XML:  coverage.xml"
}

# Run tests in parallel (fast)
run_fast_tests() {
    log_info "Running tests in parallel..."
    local cmd
    cmd=$(build_pytest_cmd)
    $cmd -n auto "${PYTEST_ARGS[@]+"${PYTEST_ARGS[@]}"}"
}

# Run package analysis tests only
run_package_tests() {
    log_info "Running package analysis tests..."
    local cmd
    cmd=$(build_pytest_cmd)
    $cmd tests/test_package_analysis.py "${PYTEST_ARGS[@]+"${PYTEST_ARGS[@]}"}"
}

# Run GitHub Actions tests with act
run_actions_tests() {
    log_info "Running GitHub Actions tests with act..."
    
    # Check if act is available
    if ! command -v act &> /dev/null; then
        log_error "act is not installed. Install from: https://github.com/nektos/act"
        return 1
    fi
    
    # Check if we're on CI
    if [[ "${CI:-false}" == "true" ]]; then
        log_info "Skipping act tests on CI - GitHub Actions run natively"
        return 0
    fi
    
    # Run the GitHub Actions integration tests
    python tests/test_github_actions.py
}

# Run code quality checks
run_lint() {
    log_info "Running code quality checks..."
    
    echo "🔍 Running ruff (linting)..."
    uv run ruff check bin/ lib/ tests/ || log_warn "Ruff found issues"
    
    echo "🎨 Checking black (formatting)..."
    uv run black --check bin/ lib/ tests/ || log_warn "Black found formatting issues"
    
    echo "🔬 Running mypy (type checking)..."
    uv run mypy bin/ lib/ || log_warn "MyPy found type issues"
    
    log_success "Code quality checks completed"
}

# Format code
run_format() {
    log_info "Formatting code..."
    
    echo "🎨 Running black (formatter)..."
    uv run black bin/ lib/ tests/
    
    echo "🔧 Running ruff (auto-fix)..."
    uv run ruff check --fix bin/ lib/ tests/ || true
    
    log_success "Code formatting completed"
}

# Clean test artifacts
run_clean() {
    log_info "Cleaning test artifacts..."
    
    rm -rf .pytest_cache/
    rm -rf htmlcov/
    rm -rf .coverage
    rm -f coverage.xml
    rm -rf .mypy_cache/
    rm -rf .ruff_cache/
    
    # Clean any stray cache files
    find . -name "*.pyc" -delete
    find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
    
    log_success "Test artifacts cleaned"
}

# Execute the command
case "$COMMAND" in
    "unit")
        run_unit_tests
        ;;
    "integration")
        run_integration_tests
        ;;
    "all")
        run_all_tests
        ;;
    "coverage")
        run_coverage_tests
        ;;
    "fast")
        run_fast_tests
        ;;
    "package")
        run_package_tests
        ;;
    "actions")
        run_actions_tests
        ;;
    "lint")
        run_lint
        ;;
    "format")
        run_format
        ;;
    "clean")
        run_clean
        ;;
    *)
        log_error "Unknown command: $COMMAND"
        echo "Try '$0 --help' for more information." >&2
        exit 1
        ;;
esac