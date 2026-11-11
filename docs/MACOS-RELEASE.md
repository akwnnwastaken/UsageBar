# Production release for macOS and Windows

UsageBar publishes separate macOS and Windows releases from the same reviewed
`main` commit. The **macOS release candidate** workflow builds and tests both
platforms. Pull requests and manual runs with an empty tag produce staging
artifacts without signing credentials or GitHub Release write access.

## Repository setup

1. In **Settings → Branches**, protect `main` with reviewed pull requests and
   the required GitHub Actions `build-and-test` check. Preserve the strict
   up-to-date check and admin enforcement. Review the pinned macOS toolchain
   job, Windows CI and CodeQL on the final SHA as release gates.
2. In **Settings → Rules → Rulesets**, protect both `v*` and `windows-v*` tags.
   Use an active tag ruleset to restrict creation to designated release
   maintainers, and a separate active rule to restrict updates and deletions
   without a routine bypass. In **Settings → General → Releases**, verify
   [release immutability](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-immutable-releases/enabling-release-immutability)
   is enabled.
3. In **Settings → Environments**, explicitly create `macos-production-signing`.
   Choose **Selected branches and tags** and allow only the **branch** `main`.
   Add a trusted independent reviewer under **Required reviewers**, enable
   **Prevent self-review**, and clear **Allow administrators to bypass
   configured protection rules**. Arrange a separate eligible dispatcher and
   reviewer before attempting production signing. Verify the saved rules
   before adding any credentials.

## Apple credentials

1. The Apple Developer Program Account Holder creates or selects a valid
   [Developer ID Application certificate](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/)
   for the team's macOS distribution. On a trusted Mac, use Keychain Access to
   create the certificate signing request, import the issued certificate on
   the same Mac and export that identity (certificate and matching private
   key) as a password-protected `.p12`. ZIP distribution needs the Application
   identity.
2. In **App Store Connect → Users and Access → Integrations → App Store
   Connect API → Team Keys**, have the Account Holder enable API access if
   needed. An authorized maintainer creates a dedicated
   [team API key](https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api)
   with the minimum role your team uses for notarization. Save the Key ID and
   Issuer ID and download the private `.p8` once. Keep both private files and
   the export password in approved secure storage.
3. Under **Settings → Environments → macos-production-signing**, add these
   environment variables: `APPLE_TEAM_ID` (Developer Program membership Team
   ID), `APPLE_NOTARY_KEY_ID`, `APPLE_NOTARY_ISSUER_ID`. Add these environment
   secrets: `APPLE_DEVELOPER_ID_P12_BASE64`, `APPLE_DEVELOPER_ID_P12_PASSWORD`
   and `APPLE_NOTARY_KEY_P8_BASE64`. Keep all six names environment-scoped.
   Enter the password through GitHub's secret field. On a trusted Mac, pipe
   the files directly into GitHub CLI, using private paths and your own
   authenticated account:

   ```bash
   base64 < /private/path/UsageBar-signing.p12 | tr -d '\n' |
     gh secret set APPLE_DEVELOPER_ID_P12_BASE64 --repo akwnnwastaken/UsageBar --env macos-production-signing
   base64 < /private/path/AuthKey.p8 | tr -d '\n' |
     gh secret set APPLE_NOTARY_KEY_P8_BASE64 --repo akwnnwastaken/UsageBar --env macos-production-signing
   ```

   Verify secret names with `gh secret list --env macos-production-signing`.
   Keep secret values out of chat, source, logs, shell arguments and artifacts.
   Leave `MACOS_RELEASE_APPROVED_SHA` unset until the final SHA is approved.

## Prepare the release pair

1. Merge all approved release changes, including features and changelog
   entries, before choosing the candidate SHA. Keep public download links and
   signing claims aligned with the published release until the new assets
   are live. Dispatch **macOS release candidate** on `main` with an empty
   tag. On the exact main SHA, verify the secret scans, macOS tests and
   packaging, and Windows package verification and installer
   install/upgrade/uninstall smoke. Check the ordinary macOS CI, pinned
   toolchain lane and CodeQL for the same SHA. Review the Windows NuGet
   audit, which includes transitive dependencies and fails on high/critical
   advisories or a failed advisory lookup.
2. Require a **passing full security audit** before the first production release, after a material security boundary change, and whenever a verified full baseline is unavailable. Cloudflare and the alternative full audit are eligible methods:
   - **Cloudflare** requires all six phases, the coverage ledger, and independent validation of findings.
   - **Alternative** requires a complete architecture and trust-boundary coverage matrix, verified SAST scope, separate source and accessible-history secret scans, supply-chain review, source review, isolated regression evidence where required, and independent verification. A successful CI run, an empty scan result, or a partial Cloudflare audit cannot satisfy this method.
   - For a smaller change, require a passing incremental review against an applicable full baseline of the **same method**, with an exact diff, unchanged trust assumptions, and targeted checks and revalidation.
   - Retain the report and evidence for the **exact** main SHA and carry unresolved findings forward across methods. Leave `MACOS_RELEASE_APPROVED_SHA` unset while required coverage or verification is incomplete, a confirmed critical/high issue or unresolved secret remains, or a plausible high-impact blocker is still unverified. Record any eligible low/medium residual-risk acceptance for that SHA, with an owner and follow-up. Method eligibility does not approve a SHA or authorize credentials, signing, a tag, or publication.
3. Obtain authorization for the two tags and for signing. Confirm the version
   matches in `Info.plist` and `windows/Directory.Build.props` and that neither
   release or draft exists. Create signed annotated tags `vX.Y.Z` and
   `windows-vX.Y.Z` on the same approved SHA. Push both together and verify
   GitHub reports both signatures as verified. Coordinate a pause in merges
   through draft creation, since the workflow requires the SHA to remain the
   `main` tip. Set the environment variable `MACOS_RELEASE_APPROVED_SHA` to
   the full approved commit SHA.

   ```bash
   # Set version and approved_sha to the reviewed version and full SHA first.
   git tag -s "v$version" "$approved_sha"
   git tag -s "windows-v$version" "$approved_sha"
   git push --atomic origin "refs/tags/v$version" "refs/tags/windows-v$version"
   ```

4. Dispatch **macOS release candidate** on `main` with `vX.Y.Z`. The protected
   signing job waits for both builds. The environment reviewer checks the
   exact SHA, both tags and the audit and CI evidence before approving. The
   workflow signs with a temporary keychain, requires Apple Accepted, staples
   the app, verifies Gatekeeper, attests the final ZIP, and creates a macOS
   draft with a checksum and provenance. Verify the run completed successfully
   and retain its run ID and attempt.
5. Download the two Windows artifacts from **the same tagged workflow run and
   successful attempt**. Check the run SHA, the package and installer
   verification logs, and both SHA-256 manifests. Then create the Windows
   draft for the existing verified `windows-vX.Y.Z` tag. Attach only the
   following files. Include the source SHA, run URL, checksum values, Windows
   testing status and unsigned/SmartScreen status in the notes. Compare
   GitHub's stored asset digests with the four local files.

   | CI artifact | Draft files |
   | --- | --- |
   | `UsageBar-Windows-Installer-x64` | `UsageBar-Setup-x64.exe` and `UsageBar-Setup-x64.exe.sha256` |
   | `UsageBar-Windows-x64` | `UsageBar-Windows-x64.zip` and `UsageBar-Windows-x64.zip.sha256` |

   To check the Windows manifests on a Mac, run these commands from the
   download directory:

   ```bash
   shasum -a 256 -c UsageBar-Setup-x64.exe.sha256
   shasum -a 256 -c UsageBar-Windows-x64.zip.sha256
   ```

## Accept and publish the drafts

1. Download the macOS draft through a browser on a clean Apple Silicon Mac.
   Check SHA-256 and the attestation for the approved `refs/heads/main` SHA,
   then check the extracted app's Developer ID, stapled ticket and Gatekeeper
   assessment. Test launch, provider login, Keychain access and Launch at
   Login with the new identity. For the first release without Mobile Sync,
   also check the upgrade from a legacy paired setup using the
   [retirement guide](retired-mobile-sync.md) on a disposable Mac.

   ```bash
   gh attestation verify "UsageBar-$version-macOS-arm64.zip" \
     --repo akwnnwastaken/UsageBar \
     --signer-workflow akwnnwastaken/UsageBar/.github/workflows/release-candidate.yml \
     --source-ref refs/heads/main --source-digest "$approved_sha" --deny-self-hosted-runners
   xcrun stapler validate UsageBar.app
   spctl --assess --type execute --verbose=4 UsageBar.app
   ```

2. On a Windows x64 test machine verify first launch, tray and provider
   behavior, and upgrade from the current public installer. Follow the
   [Windows checklist](windows-port.md#13-windows-installer-physical-test-checklist)
   and record what was tested. Windows CI does not replace a hands-on check
   of a supported desktop, including the oldest Windows version claimed for
   the release. Keep SmartScreen and Defender enabled.
3. Review both drafts, exact digests, smoke results and release notes together.
   Obtain explicit approval for both before publishing them in one release
   window. GitHub publishes the two drafts separately. If the second publish
   fails, keep the verified tags and assets intact and resolve the failure
   before updating download links. Verify both releases and their asset
   digests are public and immutable, update README links and signing claims,
   and clear `MACOS_RELEASE_APPROVED_SHA`.

A pre-existing public release stops signing. Before dispatch, check for private
drafts as well. The draft job refuses to overwrite either tag's release or
draft. Inspect failed or abandoned drafts with the maintainer before retrying.
