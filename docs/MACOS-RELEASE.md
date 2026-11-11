# Production release for macOS and Windows

UsageBar uses a solo maintainer model. macOS `v2.5.0` and Windows
`windows-v2.5.0` can ship on different dates from separately reviewed
`main` commits. The macOS release workflow uses only the macOS tag and macOS
build. Pull requests still build and test both platforms. A manual dispatch
with empty inputs produces staging artifacts for the selected platform.

## Repository setup

1. In **Settings → Branches**, require pull requests to `main` with zero
   required human approvals and the required GitHub Actions `build-and-test`
   check. Preserve the strict up-to-date check, admin enforcement and blocks
   on force pushes and deletion. Review the pinned macOS toolchain job
   and CodeQL results on the final macOS SHA. Review Windows CI on the
   final Windows SHA.
2. In **Settings → Rules → Rulesets**, protect both `v*` and `windows-v*` tags.
   In an active tag ruleset, enable **Restrict creations** and give bypass
   access to the repository owner. In a separate active ruleset for
   the same patterns, enable **Restrict updates** and **Restrict deletions**
   with an empty bypass list. In **Settings → General → Releases**, verify
   [release immutability](https://docs.github.com/en/code-security/how-tos/secure-your-supply-chain/establish-provenance-and-integrity/prevent-release-changes)
   is enabled.
3. In **Settings → Environments**, explicitly create `macos-production-signing`.
   Choose **Selected branches and tags** and allow only the **branch** `main`.
   Leave **Required reviewers** unset. Verify the saved branch rule and
   confirm the owner-only workflow is on protected `main` before loading any
   credentials. The workflow checks both settings before entering
   the environment and again before the signing step reads the secrets.

## Solo maintainer security policy

The owner keeps the security assessment, signing authorization and publication
decision as separate steps. The same person performs them. One compromised
owner account can change repository settings and authorize a release, and one
person can miss a defect that a second reviewer would catch. Required
automated checks, separate staging and signing jobs, exact-commit checks and
environment-scoped credentials reduce exposure to workflow mistakes and
untrusted branches. They provide no independent human review. Protect the owner
account with phishing-resistant two-factor authentication and retain GitHub run
records and approval evidence for the release SHA.

Require a full security assessment for the first Developer ID release, after
a material trust-boundary change, or when an applicable full baseline is
missing. The maintainer's full assessment includes:

- Architecture and trust-boundary inventory and a coverage record.
- CodeQL or equivalent static analysis with checked coverage, separate
  tree and accessible-history secret scans, and dependency/supply-chain review.
- Maintainer source review, isolated regression evidence where needed, and
  recorded disposition of findings and coverage gaps.

For a smaller change, review the exact diff against an applicable full
baseline and rerun the affected checks. A prior independent audit can be used
as evidence where its scope still applies. Record who reviewed each result
and which parts were automated. An incomplete independent audit or a green CI
run alone does not satisfy this policy.

Retain dated evidence for the exact final `main` SHA. Carry unresolved
findings forward. Leave `MACOS_RELEASE_APPROVED_SHA` unset while required
coverage is incomplete, critical/high issues or unresolved secrets remain,
or a plausible high-impact concern is still unverified. Document the owner,
rationale and follow-up for any accepted low/medium residual risk.

## Apple credentials

1. The Apple Developer Program Account Holder creates or selects a valid
   [Developer ID Application certificate](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/)
   for the team's macOS distribution. On a trusted Mac, in **Keychain Access
   → Certificate Assistant → Request a Certificate From a Certificate
   Authority**, save the request to disk. Use that request in Apple Developer,
   import the issued certificate on the same Mac, and export the identity
   from **My Certificates** (certificate and matching private key) as a
   password-protected `.p12`. ZIP distribution needs the Application identity.
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

## Prepare and publish macOS

1. Merge approved macOS release changes, including the changelog. Keep public
   download links and signing claims aligned with the published release.
   Dispatch **macOS release candidate** on `main` with both inputs empty.
   On the exact `main` SHA, check the required build, pinned toolchain,
   staging tests, package checks, secret scans and CodeQL.
2. Complete the full security assessment for that SHA. Record the evidence
   and the owner's separate decision authorizing the release steps below.
   Check that the SHA is still the current `main` tip and that the macOS
   version has no release or draft. Pause merges through draft creation.
3. Record the full approved commit in `MACOS_RELEASE_APPROVED_SHA` in the
   protected signing environment. After the owner authorizes tag creation,
   confirm the version in `Info.plist`, create the signed annotated macOS
   tag and verify that GitHub reports the signature as verified.

   ```bash
   # Set version and approved_sha to the reviewed version and full SHA first.
   git tag -s "v$version" "$approved_sha"
   git push origin "refs/tags/v$version"
   ```

4. After the owner authorizes signing and notarization, dispatch **macOS
   release candidate** on `main` from the repository owner's account. Enter
   `vX.Y.Z` for `tag` and the full approved commit for `release_sha`.
   The run, current `main` tip, verified macOS tag and
   `MACOS_RELEASE_APPROVED_SHA` must identify the same commit. The signing
   job uses a temporary keychain, requires Apple Accepted, staples the app
   and verifies Gatekeeper and the final archive. The draft job attests the
   final ZIP, attaches its checksum and provenance, and checks GitHub's
   stored asset digests. Retain the successful run ID and attempt.
5. Download the macOS draft through a browser on a clean Apple Silicon Mac.
   Verify the checksum, attestation for the approved SHA, Developer ID,
   stapled ticket and Gatekeeper assessment. Test first launch, provider
   login, Keychain access and Launch at Login under the new signing identity.
   For the first release without Mobile Sync, also check upgrade from a
   legacy paired setup using the [retirement guide](retired-mobile-sync.md)
   on a disposable Mac.

   ```bash
   shasum -a 256 -c "UsageBar-$version-macOS-arm64.zip.sha256"
   gh attestation verify "UsageBar-$version-macOS-arm64.zip" \
     --repo akwnnwastaken/UsageBar \
     --signer-workflow akwnnwastaken/UsageBar/.github/workflows/release-candidate.yml \
     --source-ref refs/heads/main --source-digest "$approved_sha" --deny-self-hosted-runners
   codesign --verify --deep --strict UsageBar.app
   codesign --display --verbose=4 UsageBar.app
   xcrun stapler validate UsageBar.app
   spctl --assess --type execute --verbose=4 UsageBar.app
   ```

6. After successful Mac acceptance and explicit publication authorization,
   publish the macOS draft for the verified digest. Verify that the public
   release is immutable with `gh release verify` and check the assets with
   `gh release verify-asset`. Update the macOS
   download links and signing claims, then clear `MACOS_RELEASE_APPROVED_SHA`.

A pre-existing macOS release stops signing. Check for macOS drafts before
dispatch. The draft job refuses to overwrite a macOS release or draft. Inspect
a failed or abandoned draft with the maintainer before retrying.

## Prepare and publish Windows separately

1. Pick and review the exact current `main` SHA for Windows. Run **Windows
   CI** on that commit with empty inputs. Review the NuGet audit, which
   includes transitive dependencies and fails on high/critical advisories
   or an unavailable advisory lookup. Verify tests, package and installer
   metadata, and install/upgrade/uninstall smoke. Complete the
   [Windows acceptance checklist](windows-port.md#13-windows-installer-physical-test-checklist)
   on supported physical x64 hardware before creating a release tag. Keep
   SmartScreen and Defender enabled.
2. With owner authorization, confirm version metadata in
   `windows/Directory.Build.props` and check that the Windows release or
   draft does not already exist. Create and push only the signed annotated
   Windows tag for the approved Windows SHA.

   ```bash
   git tag -s "windows-v$version" "$approved_sha"
   git push origin "refs/tags/windows-v$version"
   ```

3. From the owner's account, dispatch **Windows CI** on protected `main`
   with the Windows tag and full approved SHA. It verifies the tag
   signature, target, SHA and Windows version before building. Download the
   following artifacts from that successful tagged dispatch and its exact
   attempt. Check source-revision and package verification logs and the
   manifests, and repeat the relevant physical acceptance checks with
   those exact files if their digests differ from the tested packages.

   | CI artifact | Draft files |
   | --- | --- |
   | `UsageBar-Windows-Installer-x64` | `UsageBar-Setup-x64.exe` and `UsageBar-Setup-x64.exe.sha256` |
   | `UsageBar-Windows-x64` | `UsageBar-Windows-x64.zip` and `UsageBar-Windows-x64.zip.sha256` |

   ```bash
   shasum -a 256 -c UsageBar-Setup-x64.exe.sha256
   shasum -a 256 -c UsageBar-Windows-x64.zip.sha256
   ```

4. Create a Windows-only draft for the existing verified tag. Record the
   source SHA, run URL and attempt, checksum values, physical test results
   and unsigned/SmartScreen status in the notes. Compare GitHub's stored
   asset digests with the verified files. Publish after the owner explicitly
   approves the draft. Check public immutability and digests, then update
   the Windows download links.
