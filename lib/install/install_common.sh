
# NOTE: this file is only meant to be sourced by other scripts.
# It is not meant to be executed directly.

set -euo pipefail

if [ -n "$BUILD_VERSION" ]; then
  echo "BUILD_VERSION: $BUILD_VERSION"
fi

# for debugging, uncomment the following line and set the
# GUM_DEBUG_LEVEL to "debug".
# set -x
export GUM_LOG_LEVEL=info
