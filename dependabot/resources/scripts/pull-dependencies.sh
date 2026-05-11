#!/usr/bin/env bash
# Pulls Ballerina Central dependencies with retries.
# Must be called from the repo root (workflow working directory).
set -euo pipefail

cd dependabot
bal clean

# Retry on failure without clearing the cache — partial downloads accumulate
# across retries and clearing the cache makes things worse.
MAX_RETRIES=5
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    echo "Pulling dependencies, attempt $((RETRY_COUNT + 1)) of $MAX_RETRIES..."
    bal build 2>&1 | tee /tmp/bal_build.log
    BUILD_EXIT=${PIPESTATUS[0]}
    if [ $BUILD_EXIT -eq 0 ]; then
        echo "Dependencies pulled successfully"
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
        echo "Pull failed — retrying in 60 seconds (cache kept)..."
        sleep 60
    else
        echo "Failed to pull dependencies after $MAX_RETRIES attempts"
        cat /tmp/bal_build.log
        exit 1
    fi
done
