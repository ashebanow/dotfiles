#!/usr/bin/env bash
#
# Fix SSL configuration issues (common on macOS with LibreSSL)
# Downgrades urllib3 to v1.x for compatibility
#

set -euo pipefail

echo "Fixing SSL configuration issues..."

# Check current status
echo "Current SSL setup:"
uv run -c "import ssl; print(f'  SSL: {ssl.OPENSSL_VERSION}')" 2>/dev/null || echo "  SSL: Failed to detect"
uv run -c "import urllib3; print(f'  urllib3: {urllib3.__version__}')" 2>/dev/null || echo "  urllib3: Not installed"

echo
echo "Applying fix: Downgrade urllib3 to v1.x (compatible with LibreSSL)"
uv run -m pip install --user 'urllib3<2.0' 'requests>=2.28.0'

echo
echo "Verifying fix..."
uv run -c "import urllib3; print(f'✓ urllib3 version: {urllib3.__version__}')"
uv run -c "import ssl, requests; print('✓ SSL/requests working'); requests.get('https://httpbin.org/get', timeout=5)" 2>/dev/null && echo "✓ HTTPS requests working" || echo "✗ HTTPS requests still failing"