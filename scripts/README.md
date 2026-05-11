# Release scripts

## `release.sh`

Builds, signs, notarizes, staples, and packages SandFestival into a DMG ready
for upload to a GitHub Release.

### One-time setup

1. **Developer ID Application certificate** installed in your login keychain.
   Verify with `security find-identity -v -p codesigning` — should list
   `Developer ID Application: ...` for team `WFV2YU28PC`.
2. **App Store Connect API key** for notarization. Get one from
   App Store Connect → Users and Access → Integrations → App Store Connect API
   (Developer role is enough). Download the `.p8` once and keep it safe.
3. **`create-dmg`** (optional, recommended): `brew install create-dmg`.
   Without it the script falls back to `hdiutil`, which works but produces a
   plainer installer window.

### Running

Export the notary credentials, then run from the repo root:

```bash
export NOTARY_KEY_ID=ABCDEF1234              # the Key ID from App Store Connect
export NOTARY_ISSUER_ID=00000000-0000-...    # Issuer UUID
export NOTARY_KEY_PATH=~/.private/AuthKey_ABCDEF1234.p8

./scripts/release.sh
```

The DMG and its SHA256 land in `build/SandFestival-<version>.dmg`. The SHA256
is what you paste into the Homebrew cask formula.

### Iterating without notarization

Notarization round-trips to Apple and takes a few minutes. For quick local
verification of the archive + sign + DMG steps, set `SKIP_NOTARIZE=1`:

```bash
SKIP_NOTARIZE=1 ./scripts/release.sh
```

The resulting DMG will trigger Gatekeeper warnings — only use these builds for
local testing.

### Version bumps

The script reads `MARKETING_VERSION` directly from
`SandFestival.xcodeproj/project.pbxproj`. To cut a new release, bump that
value (all six occurrences — main, Tests, UITests × Debug, Release), commit,
tag `vX.Y.Z`, then run the script.

## `ExportOptions.plist`

Used by `xcodebuild -exportArchive` to produce a Developer ID-signed `.app`
suitable for direct distribution (not Mac App Store). Hardcodes the team ID
and uses automatic signing.
