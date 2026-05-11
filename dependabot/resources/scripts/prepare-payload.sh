#!/usr/bin/env bash
# Builds the connector orchestration dispatch payload from UPDATE_SUMMARY.json.
# Writes connector_count and malformed_count to GITHUB_OUTPUT.
# Writes the dispatch payload to /tmp/dispatch_payload.json.
set -euo pipefail

echo "Preparing connector update payload..."

CONNECTORS_JSON="[]"
CONNECTOR_COUNT=0
MALFORMED_SPECS="[]"
MALFORMED_COUNT=0

if [ -f "UPDATE_SUMMARY.json" ]; then
    echo "Reading UPDATE_SUMMARY.json:"
    cat UPDATE_SUMMARY.json
    echo ""

    while IFS= read -r entry; do
        [ -z "$entry" ] && continue

        CONNECTOR_REPO=$(echo "$entry" | jq -r '.connectorRepo // empty')
        VENDOR=$(echo "$entry" | jq -r '.vendor')
        API_ID=$(echo "$entry" | jq -r '.apiId')
        VERSION=$(echo "$entry" | jq -r '.version')

        if [ -z "$CONNECTOR_REPO" ]; then
            echo "Warning: no connectorRepo for $VENDOR/$API_ID@$VERSION — skipping"
            continue
        fi

        SPEC_URL_BASE="https://raw.githubusercontent.com/${GITHUB_REPOSITORY}/main/openapi/${VENDOR}/${API_ID}/${VERSION}"
        SPEC_URL="${SPEC_URL_BASE}/openapi.json"
        if ! curl -sf --head "$SPEC_URL" > /dev/null 2>&1; then
            SPEC_URL="${SPEC_URL_BASE}/openapi.yaml"
        fi

        ITEM=$(jq -n \
            --arg repo "$CONNECTOR_REPO" \
            --arg spec "${VENDOR}/${API_ID}" \
            --arg ver "$VERSION" \
            --arg url "$SPEC_URL" \
            '{"repository": $repo, "specification": $spec, "version": $ver, "openapi_url": $url}')
        CONNECTORS_JSON=$(echo "$CONNECTORS_JSON" | jq --argjson item "$ITEM" '. + [$item]')
        CONNECTOR_COUNT=$((CONNECTOR_COUNT + 1))
        echo "Added: $CONNECTOR_REPO -> $SPEC_URL"
    done < <(jq -c '.updated[]' UPDATE_SUMMARY.json)

    MALFORMED_SPECS=$(jq '.malformed' UPDATE_SUMMARY.json)
    MALFORMED_COUNT=$(echo "$MALFORMED_SPECS" | jq 'length')
fi

echo "connector_count=$CONNECTOR_COUNT" >> "$GITHUB_OUTPUT"
echo "malformed_count=$MALFORMED_COUNT" >> "$GITHUB_OUTPUT"

jq -n \
    --argjson connectors "$CONNECTORS_JSON" \
    --argjson malformed "$MALFORMED_SPECS" \
    '{"event_type": "orchestrate-connector-updates", "client_payload": {"connectors": $connectors, "malformed_specs": $malformed}}' \
    > /tmp/dispatch_payload.json

echo "Payload ready: $CONNECTOR_COUNT connector(s), $MALFORMED_COUNT malformed spec(s)"
echo "Dispatch payload:"
cat /tmp/dispatch_payload.json
