#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_IPA="${PROJECT_DIR}/Shift.ipa"
BUILD_DIR="${PROJECT_DIR}/.build_temp"

echo "=========================================="
echo "⚡️ Building Shift iOS App (.ipa Package)"
echo "=========================================="

# Ensure developer tools are targeted
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

# Clean up old build temp
rm -rf "${BUILD_DIR}" "${OUTPUT_IPA}"
mkdir -p "${BUILD_DIR}/Payload"

echo "🔨 Compiling Release ARM64 binary..."
xcodebuild -project "${PROJECT_DIR}/ADM.xcodeproj" \
    -scheme "ADM" \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    CONFIGURATION_BUILD_DIR="${BUILD_DIR}/Products" \
    build -quiet

echo "📦 Packaging App into Payload..."
cp -R "${BUILD_DIR}/Products/ADM.app" "${BUILD_DIR}/Payload/Shift.app"

echo "🗜 Creating Shift.ipa..."
cd "${BUILD_DIR}"
zip -qr -9 "${OUTPUT_IPA}" Payload
cd "${PROJECT_DIR}"

# Clean up temp files
rm -rf "${BUILD_DIR}"

echo "=========================================="
echo "✅ Build Complete!"
echo "📍 IPA generated at: ${OUTPUT_IPA}"
echo "📊 Size: $(ls -lh "${OUTPUT_IPA}" | awk '{print $5}')"
echo "=========================================="
