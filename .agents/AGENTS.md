# my5top Workspace Rules

## Release Bumping Rule
Whenever proposing a release title/notes, check the current `version:` line in `pubspec.yaml` and proactively check if we need to bump it, or bump it directly, to keep the GitHub release version tag and local app build versions perfectly in sync.

## Post-Walkthrough Version Query Rule
Whenever the user asks for changes to the app *after* a walkthrough has been completed, you must ask them:
"Do you want to update the `pubspec.yaml` file so the app can detect the new changes in the update (using the same version number or a new one)?"
Wait for the user's answer:
- If the user chooses to keep the version number the same, update `release_notes.md` and provide new patch/release notes updating the current version's notes and title to include the recent changes, then immediately stage, commit, and push the changes to `origin main` (which automatically rebuilds and updates the GitHub Release APK).
- If the user provides a new version number (or confirms bumping to a new version), update `pubspec.yaml` to that version (proactively bumping the build number and syncing `AppState`), update `release_notes.md` (`# vX.Y.Z — Title` on line 1 + Markdown body), immediately stage, commit, and push the changes to `origin main` (without asking a second time), and provide the new release title and release notes matching the new version number.
These notes and titles should be formatted in Markdown, ready to copy-paste directly into a GitHub release.

## Global Dynamic System Navigation Bar & SafeArea Padding Rule
All pages, screens, and modal overlays must dynamically respect the device's bottom system navigation bar inset (`SafeArea` / `MediaQuery.paddingOf(context).bottom` / `viewPadding.bottom`) so scrolling content or buttons are never obscured by or visible underneath persistent Android/Samsung 3-button navigation bars or gesture bars.

## Prefix-Matchable Single Git Commands Rule
Never chain `git add`, `git commit`, and `git push` into a single command with `;` or `&&`, and avoid quotes or shell constructs that break prefix-matching approvals. Always invoke `git add -A`, `git commit -m ...`, and `git push origin main` as separate individual `run_command` calls.

## Release Notes Style Rule (No External App Inspirations)
Never reference external app inspirations in release titles, release notes, or user-facing changelog descriptions. Always highlight and describe the feature itself directly on its own merits.

## Verify Live GitHub Release & APK Asset Rule
After pushing a release or patch commit to `origin main`, NEVER tell the user the release is done until the GitHub Actions workflow has finished succeeding and you have verified via `gh release view` that the release is live in GitHub Releases with the compiled `.apk` asset uploaded and available.

