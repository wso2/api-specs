#!/usr/bin/env bash
# Builds the openapi-validator fat JAR and wires it into the Ballerina project.
#
# After running this script, Java-based spec validation is enabled and provides
# more accurate validation than the keyword heuristic (looksLikeSpec).
#
# Prerequisites: Java 11+ JDK  and  Maven 3.x
#   macOS:   brew install openjdk maven
#   Ubuntu:  apt install openjdk-21-jdk maven
#
# Usage:
#   cd java-validator
#   ./build.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LIBS_DIR="${PROJECT_ROOT}/libs"
JAR_NAME="openapi-validator.jar"
BAL_FILE="${PROJECT_ROOT}/openapi_validator.bal"
BAL_EXAMPLE="${BAL_FILE}.example"
TOML="${PROJECT_ROOT}/Ballerina.toml"

echo "==> Building openapi-validator fat JAR..."
cd "$SCRIPT_DIR"
mvn package -DskipTests -q

FAT_JAR="${SCRIPT_DIR}/target/openapi-validator-1.0.0-jar-with-dependencies.jar"
if [ ! -f "$FAT_JAR" ]; then
    echo "ERROR: fat JAR not found at ${FAT_JAR}"
    exit 1
fi

echo "==> Copying JAR to ${LIBS_DIR}/${JAR_NAME}..."
mkdir -p "$LIBS_DIR"
cp "$FAT_JAR" "${LIBS_DIR}/${JAR_NAME}"

echo "==> Activating openapi_validator.bal..."
if [ -f "$BAL_EXAMPLE" ] && [ ! -f "$BAL_FILE" ]; then
    cp "$BAL_EXAMPLE" "$BAL_FILE"
    echo "    Copied openapi_validator.bal.example → openapi_validator.bal"
fi

echo "==> Uncommenting platform dependency in Ballerina.toml..."
# Uncomment the [[platform.java21.dependency]] block (portable: BSD and GNU sed)
_sed_inplace() { pattern="$1"; file="$2"; tmp=$(mktemp); sed "$pattern" "$file" > "$tmp" && mv "$tmp" "$file"; }
_sed_inplace 's|^# \[\[platform\.java21\.dependency\]\]|[[platform.java21.dependency]]|' "$TOML"
_sed_inplace 's|^# path = "libs/openapi-validator.jar"|path = "libs/openapi-validator.jar"|' "$TOML"

echo ""
echo "==> Done!"
echo "    Java OpenAPI validation is now enabled."
echo "    Run: bal run ."
