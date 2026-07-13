# Releasing Victor (victor-dst / #49)

Direct-download distribution: Developer ID signing + hardened runtime +
notarization. No App Sandbox (see #45 — closed won't-fix: sandbox is Mac App
Store-only and incompatible with spawning user-installed `hugo`/`git`).

## One-time setup

1. **Developer ID Application certificate** — already in the login keychain
   (`Developer ID Application: Karan Juneja (55V96YBUQ4)`). If it ever needs
   recreating: Xcode → Settings → Accounts → Manage Certificates, or
   developer.apple.com → Certificates.
2. **Notarization credentials** (interactive, ~2 min):
   - Create an app-specific password at account.apple.com → Sign-In and
     Security → App-Specific Passwords.
   - Store it: `xcrun notarytool store-credentials victor-notary --apple-id
     <your-apple-id> --team-id 55V96YBUQ4` (paste the app-specific password
     when prompted). This writes a keychain item; the release script finds it
     by the `victor-notary` profile name.

## Cutting a release

1. Bump `MARKETING_VERSION` (and `CURRENT_PROJECT_VERSION`) in `project.yml`.
2. Run `scripts/release.sh`. It: regenerates the project, archives Release
   (hardened runtime on, Developer ID identity, secure timestamp), verifies
   the signature, zips, submits to Apple notarization and waits, staples the
   ticket, re-zips, and runs a final Gatekeeper `spctl` assessment.
   - Without stored credentials it stops after signing (exit 2) and leaves a
     signed-but-unnotarized zip plus setup instructions.
3. Publish: `gh release create v<version> build/release/Victor-<version>.zip
   --title "Victor <version>"` with notes.
4. Sanity check on another machine (or a fresh user account): download,
   unzip, launch — no right-click-open ritual should be needed.

## DMG (optional)

`scripts/release.sh --dmg` additionally produces a drag-to-Applications DMG:
built with `create-dmg` (`brew install create-dmg`), signed with the same
Developer ID identity, notarized, and stapled in its own right (the app
inside is already stapled — Gatekeeper is satisfied at both layers).
Layout: app icon left, Applications symlink right, 660×420 window.
`scripts/dmg-background.png` is used as the window background if present;
until the app-icon redesign (#36) delivers matching art, omitting it gives a
plain (acceptable) window. The zip remains the canonical artifact — publish
both.

## Notes

- The entitlements file (`Victor/Victor.entitlements`) is deliberately empty:
  hardened runtime needs no exceptions for `Process`-spawned hugo or WKWebView.
- Debug builds keep automatic signing and no hardened runtime (debugger
  attachment).
- Future (separate issues when wanted): CI automation, Sparkle updates.
