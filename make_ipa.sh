#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_IPA="${PROJECT_DIR}/Shift.ipa"
PAYLOAD_DIR="${PROJECT_DIR}/Payload"

echo "=========================================="
echo "⚡️ Packaging Shift.ipa from Xcode Build"
echo "=========================================="

# Find the latest built real .app in DerivedData (excluding Index.noindex)
BUILT_APP=$(find ~/Library/Developer/Xcode/DerivedData -type d -path "*/Build/Products/*-iphoneos/Shift.app" -not -path "*/Index.noindex/*" 2>/dev/null | head -n 1)

if [ -z "${BUILT_APP}" ]; then
    # Fallback to any *-iphoneos .app
    BUILT_APP=$(find ~/Library/Developer/Xcode/DerivedData -type d -path "*/Build/Products/*-iphoneos/*.app" -not -path "*/Index.noindex/*" 2>/dev/null | head -n 1)
fi

if [ -z "${BUILT_APP}" ]; then
    echo "❌ No built iOS device .app found in DerivedData."
    echo "👉 Please build for 'Any iOS Device (arm64)' in Xcode first (Product -> Build / ⌘B)."
    exit 1
fi

echo "🔍 Found built app at:"
echo "   ${BUILT_APP}"

# 1. Create a clean Payload directory
rm -rf "${PAYLOAD_DIR}" "${OUTPUT_IPA}"
mkdir -p "${PAYLOAD_DIR}"

# 2. Copy the built .app into Payload as Shift.app
echo "📦 Copying into Payload/Shift.app..."
cp -R "${BUILT_APP}" "${PAYLOAD_DIR}/Shift.app"

# 3. Zip into Shift.ipa
echo "🗜 Compressing into Shift.ipa..."
cd "${PROJECT_DIR}"
zip -qr -9 "${OUTPUT_IPA}" Payload

# Clean up Payload directory
rm -rf "${PAYLOAD_DIR}"

echo "=========================================="
echo "✅ Shift.ipa is ready!"
echo "📍 Location: ${OUTPUT_IPA}"
echo "📊 File Size: $(ls -lh "${OUTPUT_IPA}" | awk '{print $5}')"
echo "=========================================="
