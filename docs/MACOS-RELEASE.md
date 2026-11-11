# Production release for macOS and Windows

UsageBar uses a solo maintainer model. The owner reviews one `main` commit
for separate macOS and Windows releases. The **macOS release candidate**
workflow builds and tests both platforms. Pull requests and manual runs with both inputs empty produce staging
artifacts without signing credentials or GitHub Release write access.

## Repository setup

1. In **Settings → Branches**, require pull requests to `main` with zero
   required human approvals and the required GitHub Actions `build-and-test`
   check. Preserve the strict up-to-date check, admin enforcement and blocks
   on force pushes and deletion. Review the pinned macOS toolchain job,
   Windows CI and CodeQL on the final SHA as release gates.
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

## Prepare the release pair

1. Merge all approved release changes, including features and changelog
   entries, before choosing the candidate SHA. Keep public download links and
   signing claims aligned with the published release until the new assets
   are live. Dispatch **macOS release candidate** on `main` with both inputs
   empty. On the exact main SHA, verify the secret scans, macOS tests and
   packaging, and Windows package verification and installer
   install/upgrade/uninstall smoke. Check the ordinary macOS CI, pinned
   toolchain lane and CodeQL for the same SHA. Review the Windows NuGet
   audit, which includes transitive dependencies and fails on high/critical
   advisories or a failed advisory lookup.
2. Complete the security assessment above and record the evidence and the
   owner's decision on the exact final SHA. Verify the commit is still the
   current `main` tip.
3. After the owner explicitly authorizes the two tags and signing, confirm
   the version matches in `Info.plist` and `windows/Directory.Build.props`
   and that neither platform has a release or draft for that version. Create
   signed annotated tags `vX.Y.Z` and
   `windows-vX.Y.Z` on the same approved SHA. Push both together and verify
   GitHub reports both signatures as verified. Pause merges through draft
   creation, since the workflow requires the SHA to remain the
   `main` tip. Set the environment variable `MACOS_RELEASE_APPROVED_SHA` to
   the full approved commit SHA.

   ```bash
   # Set version and approved_sha to the reviewed version and full SHA first.
   git tag -s "v$version" "$approved_sha"
   git tag -s "windows-v$version" "$approved_sha"
   git push --atomic origin "refs/tags/v$version" "refs/tags/windows-v$version"
   ```

4. From the repository owner's GitHub account, dispatch **macOS release
   candidate** on `main`. Enter `vX.Y.Z` for `tag` and the full approved
   commit for `release_sha`. The run, current `main` tip, both verified
   tags and `MACOS_RELEASE_APPROVED_SHA` must identify the same commit.
   Only the owner can start or retry production signing and draft creation.
   The signing job waits for both builds, signs with a temporary keychain,
   requires Apple Accepted, staples the app, verifies Gatekeeper, attests
   the final ZIP, and creates a macOS draft with a checksum and provenance.
   Verify the run completed successfully and retain its run ID and attempt.
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
   The owner explicitly approves both before publishing them in one release
   window. GitHub publishes the two drafts separately. If the second publish
   fails, keep the verified tags and assets intact and resolve the failure
   before updating download links. Verify both releases and their asset
   digests are public and immutable, update README links and signing claims,
   and clear `MACOS_RELEASE_APPROVED_SHA`.

For another personal repository, the same pattern binds production jobs to
GitHub's repository owner, a full approved commit, and a branch-restricted
environment. Adapt the required build jobs and signed tag checks to that
repository's release targets.

A pre-existing public release stops signing. Before dispatch, check for private
drafts as well. The draft job refuses to overwrite either tag's release or
draft. Inspect failed or abandoned drafts with the maintainer before retrying.
