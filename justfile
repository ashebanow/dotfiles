#!/usr/bin/env just --justfile

# Default recipe to show available commands
default:
    @just --list

# ===== TESTING =====

# Run install script tests (if they exist)
[group('testing')]
test-install:
    @./lib/testing/run_install_tests.sh
