# Keezly — Xcode Cloud Setup Checklist

Xcode Cloud is a binding part of the CI/CD strategy, not documentation. This
file separates what is already prepared in the repository from what only a
person with access to the Apple account can do (§116).

The three states are never blurred (§117):

| State | Meaning | Keezly today |
|---|---|---|
| **PREPARED** | Project, shared scheme, `ci_scripts` and docs exist in the repo | **YES** |
| **CONFIGURED** | Workflows exist in Xcode Cloud and are connected to GitHub | **NO** |
| **VERIFIED** | At least one real cloud build has run and passed | **NO** |

Until a real cloud build has run, Xcode Cloud is reported as PREPARED/BLOCKED
and nothing else.

---

## Already prepared (automated, nothing to do)

- [x] `Keezly.xcodeproj` committed and buildable from a clean clone
- [x] `Keezly` scheme is **shared** (`xcshareddata/xcschemes/Keezly.xcscheme`)
- [x] Scheme covers the app, `KeezlyTests` and `KeezlyUITests`
- [x] Bundle identifiers fixed: `de.gcng.keezly`, `.tests`, `.uitests`
- [x] No absolute developer-machine paths in the project
- [x] No local-only file is required to build for the simulator
- [x] `ci_scripts/ci_post_clone.sh` — logs the toolchain, sets up Bundler
- [x] `ci_scripts/ci_pre_xcodebuild.sh` — derives `CFBundleVersion` from
      `CI_BUILD_NUMBER`, verified end to end locally
- [x] `ci_scripts/ci_post_xcodebuild.sh` — reports the outcome, never reddens a
      green build
- [x] Signing team kept out of the repository (`Config/Local.xcconfig`)
- [x] Rules engine testable without a simulator (`swift test`)

---

## Manual steps — only the account holder can do these

Each needs Apple Developer or App Store Connect access. They are listed in
`CURRENT_STATE.md` under Manual Actions with their live status.

### 1. App Store Connect app record — MAN-02, **the blocker**

- [ ] Create an app record for bundle id `de.gcng.keezly`
- [ ] Name: `Keezly: Keezenspel`
- [ ] Primary language and category set

Verified empirically on 2026-09-20: the App Store Connect API lists 14 app
records for this account and `de.gcng.keezly` is not among them
(`bundle exec fastlane asc_check` reports this).

Everything below depends on this step.

### 2. Enable Xcode Cloud — MAN-04

- [ ] In Xcode: Product ▸ Xcode Cloud ▸ Create Workflow
- [ ] Grant Xcode Cloud access to `github.com/baronblk/keezly-ios`
- [ ] Select the Apple Developer team that owns the app record

### 3. Create the three workflows

**Keezly CI** — pull requests and development branches
- [ ] Start condition: pull request to `main`
- [ ] Actions: Build, Test
- [ ] Test destinations: one current iPhone **and** one current iPad
- [ ] Scheme: `Keezly`

**Keezly Main** — merges to `main`
- [ ] Start condition: branch changes on `main`
- [ ] Actions: Build, Test, Analyze
- [ ] Test destinations: several form factors, portrait and landscape

**Keezly Release** — deliberate trigger
- [ ] Start condition: manual, or a release tag
- [ ] Actions: Build, Test, Analyze, Archive
- [ ] Post-action: TestFlight distribution
- [ ] Not run on every commit

### 4. Environment

- [ ] Any App Store Connect credentials added as **environment secrets**, never
      committed (§106)
- [ ] Confirm which Ruby the current Xcode Cloud image ships, and adjust
      `ci_post_clone.sh` if Bundler needs different handling (§103)

### 5. Verify — required before claiming VERIFIED

- [ ] A real cloud build completes
- [ ] Tests pass on at least one iPhone destination
- [ ] Tests pass on at least one iPad destination
- [ ] `CFBundleVersion` in the build matches `CI_BUILD_NUMBER`
- [ ] Record the build number and result in `CURRENT_STATE.md`
- [ ] Only then mark Xcode Cloud as VERIFIED

---

## After verification

Xcode Cloud is then used actively: pull requests get CI, `main` gets the wider
run, and releases go through the release workflow to TestFlight. It does not
go back to being documentation.
