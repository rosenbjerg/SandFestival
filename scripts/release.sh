#!/usr/bin/env bash
#
# Build, sign, notarize, staple, and package SandFestival for direct distribution.
#
# Required environment variables:
#   NOTARY_KEY_ID      App Store Connect API key ID (e.g. "ABCD1234EF")
#   NOTARY_ISSUER_ID   App Store Connect issuer UUID
#   NOTARY_KEY_PATH    Filesystem path to the .p8 private key
#
# Optional:
#   SKIP_NOTARIZE=1    Build + sign + DMG only; do not submit to Apple
#
# Output:
#   build/SandFestival-<version>.dmg + sha256
#
set -euo pipefail

PROJECT="SandFestival"
SCHEME="SandFestival"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ROOT}/build"
ARCHIVE_PATH="${BUILD_DIR}/${PROJECT}.xcarchive"
EXPORT_PATH="${BUILD_DIR}/export"
EXPORT_OPTIONS="${ROOT}/scripts/ExportOptions.plist"

VERSION=$(grep -m1 -E "MARKETING_VERSION = " "${ROOT}/${PROJECT}.xcodeproj/project.pbxproj" \
  | sed -E 's/.*MARKETING_VERSION = ([^;]+);.*/\1/' \
  | tr -d ' "')

if [[ -z "${VERSION}" ]]; then
  echo "error: could not read MARKETING_VERSION from pbxproj" >&2
  exit 1
fi

echo "==> Releasing ${PROJECT} ${VERSION}"

# Nothing here bumps MARKETING_VERSION — that's a separate step — so it's easy
# to re-run against a version that already shipped. An existing tag means the
# DMG for it is already published, and rebuilding produces a *different* file
# with a different checksum. The caller would then repoint the Homebrew cask at
# that checksum while the published asset keeps the old one, breaking installs.
# Checked before the archive so this costs a second, not a full notarize cycle.
if git -C "${ROOT}" rev-parse -q --verify "refs/tags/v${VERSION}" >/dev/null; then
  echo "error: tag v${VERSION} already exists — bump MARKETING_VERSION before releasing" >&2
  exit 1
fi
# The tag may only exist on the remote if a release went out from elsewhere.
# Unreachable origin is not itself an error: the local check above still stands
# and the script has to work offline.
if REMOTE_TAG=$(git -C "${ROOT}" ls-remote --tags origin "refs/tags/v${VERSION}" 2>/dev/null) \
  && [[ -n "${REMOTE_TAG}" ]]; then
  echo "error: tag v${VERSION} already exists on origin — bump MARKETING_VERSION before releasing" >&2
  exit 1
fi

if [[ "${SKIP_NOTARIZE:-0}" != "1" ]]; then
  : "${NOTARY_KEY_ID:?NOTARY_KEY_ID is required (or set SKIP_NOTARIZE=1)}"
  : "${NOTARY_ISSUER_ID:?NOTARY_ISSUER_ID is required (or set SKIP_NOTARIZE=1)}"
  : "${NOTARY_KEY_PATH:?NOTARY_KEY_PATH is required (or set SKIP_NOTARIZE=1)}"
  if [[ ! -f "${NOTARY_KEY_PATH}" ]]; then
    echo "error: NOTARY_KEY_PATH does not exist: ${NOTARY_KEY_PATH}" >&2
    exit 1
  fi
fi

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

echo "==> Archiving"
xcodebuild \
  -project "${ROOT}/${PROJECT}.xcodeproj" \
  -scheme "${SCHEME}" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "${ARCHIVE_PATH}" \
  clean archive

echo "==> Exporting Developer ID build"
xcodebuild \
  -exportArchive \
  -archivePath "${ARCHIVE_PATH}" \
  -exportOptionsPlist "${EXPORT_OPTIONS}" \
  -exportPath "${EXPORT_PATH}"

APP_PATH="${EXPORT_PATH}/${PROJECT}.app"

echo "==> Verifying code signature"
codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
codesign --display --verbose=2 "${APP_PATH}" 2>&1 | grep -E "Authority|TeamIdentifier|Hardened"

notarize() {
  local artifact="$1" label="$2"
  local result="${BUILD_DIR}/notary-${label}.plist"

  echo "==> Submitting ${label} to notary service (this may take several minutes)"
  set +e
  xcrun notarytool submit "${artifact}" \
    --key "${NOTARY_KEY_PATH}" \
    --key-id "${NOTARY_KEY_ID}" \
    --issuer "${NOTARY_ISSUER_ID}" \
    --wait \
    --output-format plist > "${result}"
  local notary_exit=$?
  set -e

  if [[ -s "${result}" ]]; then
    cat "${result}"
  fi
  if [[ ${notary_exit} -ne 0 ]]; then
    local submission_id
    submission_id=$(/usr/libexec/PlistBuddy -c "Print :id" "${result}" 2>/dev/null || true)
    if [[ "${submission_id}" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
      echo "==> Notarization of ${label} failed; fetching log for ${submission_id}"
      xcrun notarytool log "${submission_id}" \
        --key "${NOTARY_KEY_PATH}" \
        --key-id "${NOTARY_KEY_ID}" \
        --issuer "${NOTARY_ISSUER_ID}" || true
    else
      echo "==> Notarization of ${label} failed before a submission ID was issued (likely an auth problem — check NOTARY_KEY_PATH / NOTARY_KEY_ID / NOTARY_ISSUER_ID)" >&2
    fi
    exit ${notary_exit}
  fi
}

if [[ "${SKIP_NOTARIZE:-0}" != "1" ]]; then
  ZIP_PATH="${BUILD_DIR}/${PROJECT}-${VERSION}.zip"
  echo "==> Zipping for notarization"
  ditto -c -k --keepParent "${APP_PATH}" "${ZIP_PATH}"

  notarize "${ZIP_PATH}" app

  echo "==> Stapling notarization ticket"
  xcrun stapler staple "${APP_PATH}"
  xcrun stapler validate "${APP_PATH}"
else
  echo "==> SKIP_NOTARIZE=1, skipping notarization and stapling"
fi

DMG_PATH="${BUILD_DIR}/${PROJECT}-${VERSION}.dmg"
echo "==> Building DMG"
if command -v create-dmg >/dev/null 2>&1; then
  create-dmg \
    --volname "${PROJECT} ${VERSION}" \
    --window-size 540 380 \
    --icon-size 96 \
    --icon "${PROJECT}.app" 140 180 \
    --app-drop-link 400 180 \
    --hide-extension "${PROJECT}.app" \
    "${DMG_PATH}" \
    "${EXPORT_PATH}"
else
  echo "    (create-dmg not installed; using hdiutil — install with 'brew install create-dmg' for a nicer installer window)"
  hdiutil create \
    -volname "${PROJECT} ${VERSION}" \
    -srcfolder "${APP_PATH}" \
    -ov -format UDZO \
    "${DMG_PATH}"
fi

# Stapler finds the ticket by the hash of the file it is stapling, and the DMG
# has a different hash from the zip notarized above — so without its own
# submission the DMG staple fails with "Record not found". Submitting only the
# DMG would be one round-trip instead of two, but then the app inside carries
# no ticket of its own and Gatekeeper has to reach Apple on first launch.
if [[ "${SKIP_NOTARIZE:-0}" != "1" ]]; then
  notarize "${DMG_PATH}" dmg

  echo "==> Stapling DMG"
  xcrun stapler staple "${DMG_PATH}"
  xcrun stapler validate "${DMG_PATH}"
fi

echo
echo "==> Done"
echo "    Artifact: ${DMG_PATH}"
shasum -a 256 "${DMG_PATH}"
