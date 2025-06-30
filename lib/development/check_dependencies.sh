#!/usr/bin/env bash
#
# Check if required Python dependencies and tools are available
# Validates SSL configuration and reports any issues
#

set -euo pipefail

echo "Checking Python dependencies..."
uv run -c "import toml; print('✓ toml library available')" 2>/dev/null || echo "✗ toml library missing (pip install toml)"
uv run -c "import requests; print('✓ requests library available')" 2>/dev/null || echo "✗ requests library missing (pip install requests)"

echo "Checking SSL configuration..."
uv run -c "import ssl; print(f'✓ SSL version: {ssl.OPENSSL_VERSION}')" 2>/dev/null || echo "✗ SSL check failed"
uv run -c "import urllib3; print(f'urllib3 version: {urllib3.__version__}')" 2>/dev/null || echo "urllib3 not available"

# Check for SSL issues
if uv run -c "import urllib3; assert urllib3.__version__.startswith('2.')" 2>/dev/null; then
    if uv run -c "import ssl; assert 'LibreSSL' in ssl.OPENSSL_VERSION" 2>/dev/null; then
        echo "⚠️  SSL Issue Detected: urllib3 v2 + LibreSSL (common on macOS)"
        echo "   Fix with: just fix-ssl"
    fi
fi

echo "Checking tools..."
command -v just >/dev/null 2>&1 && echo "✓ just available" || echo "✗ just not found"
command -v python3 >/dev/null 2>&1 && echo "✓ python3 available" || echo "✗ python3 not found"