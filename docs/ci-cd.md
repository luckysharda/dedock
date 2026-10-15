# CI/CD and Docker

How dedock is built, checked and shipped automatically. Owner: planning session (dedock-e9) for this spec and the files under `.github/`, `docker/` and `ci/`. The implementer owns `Package.swift`, `Sources/`, `Tests/` and `Scripts/`; the pipeline calls into them through the contracts in §6.

## 1. Pipeline at a glance

| Trigger | Jobs | Runner | Blocking |
|---|---|---|---|
| Push to any branch | `changes`, `guards`; `docs` if docs changed; `linux-core` if code changed | Ubuntu 24.04 (+ Docker) | `guards`, `docs` yes; `linux-core` no until §4 lands |
| PR into `develop`, `staging` or `main` | all of the above + `macos` | + macOS 26 | all except `linux-core` (until §4) |
| Push to `staging` | CI + `Release / package` → release-candidate artifact | macOS 26 | yes |
| Tag `v*` on `main` | `Release / package` → signed, notarized DMG on a **draft** GitHub Release | macOS 26 | yes |
| Manual (`workflow_dispatch`) | everything, ignoring path filters | both | — |

Files: `.github/workflows/ci.yml`, `.github/workflows/release.yml`, `.github/dependabot.yml`, `.github/pull_request_template.md`, `docker/linux-core.Dockerfile`, `docker/compose.yml`, `.markdownlint-cli2.jsonc`, `ci/*.sh`.

## 2. Jobs

| Job | What it does | Script |
|---|---|---|
| `changes` | Path filter: `code` (Package, Sources, Tests, Scripts, ci, docker, workflows) and `docs` (`docs/**`, `*.md`). Docs-only pushes never start a macOS runner. | `dorny/paths-filter@v3` |
| `guards` | No Notchy files or references; no `.worktrees/`, `.build/`, `build/` tracked; no file > 5 MB; `Scripts/check-deps.sh` (module rules D4/D5/D8 in `architecture.md`) once it exists; clean-room string guard against `ci/clean-room-strings.txt` once that list is added (`plan.md` R9). | `ci/guards.sh` |
| `docs` | markdownlint in Docker (rules relaxed for dense tables, see `.markdownlint-cli2.jsonc`); offline relative-link and anchor check with lychee. | `docker compose … docs-lint`, `lycheeverse/lychee-action@v2` |
| `linux-core` | `swift build` + `swift test` in `swift:6.2-noble` for the platform-neutral modules. Cheap feedback on every push. | `ci/linux-test.sh` via `docker compose … linux-core` |
| `macos` | Toolchain check, `swift build --build-tests`, `swift test --parallel`, release build, `Dedock.app` assembly, zip uploaded as an artifact (14 days). | `ci/macos-toolchain.sh`, `ci/build-app.sh` |
| `Release / package` | Tag must be on `main`; tests; universal build; Developer ID sign → DMG → notarize → staple → Gatekeeper check; draft release with generated notes. Without secrets it ships an ad-hoc signed zip and warns. | `ci/build-app.sh release universal`, `ci/sign-notarize.sh` |

## 3. Toolchain policy

- CI compiles with the macOS 26 runner's **Swift 6.2**, which equals `swift-tools-version: 6.2`. Local development uses Swift 6.4 (Command Line Tools). Anything that needs a newer compiler fails in CI loudly; we do not pin a newer Xcode to hide it.
- `ci/macos-toolchain.sh` fails if the compiler is older than the package's tools version.
- The hosted `macos-26` image currently ships Xcode 26.6 / Swift 6.3.3 (first run, 2026-10-15), newer than the 6.2 floor; the floor check still guards older images.
- Swift steps are skipped on refs without `Package.swift` (e.g. docs-only branches).
- The Linux image is pinned to `swift:6.2-noble` for the same reason. Dependabot proposes image and action bumps weekly against `develop`.

## 4. Linux portability rule (needed for `linux-core`)

Pure logic must build without Apple frameworks so it can run in Docker:

1. `DedockCore` and the pure Edge Dock logic (trigger geometry, reveal state machine, layout grammar) import **Foundation only**. Foundation on Linux provides `CGFloat`, `CGPoint`, `CGSize` and `CGRect`. Where CoreGraphics is unavoidable: `#if canImport(CoreGraphics) import CoreGraphics #endif`.
2. `Package.swift` gates Apple-only targets (`Dedock`, `DesignSystem`, `EventTapKit`, `DisplayTopology` AppKit parts, and their tests) behind `#if canImport(AppKit)`.
3. When both land, set the repository variable `LINUX_CORE_REQUIRED=true`; the job becomes blocking.

Status: requested from the implementer through the orchestrator on 2026-10-15; Foundation-only imports during the current refactor, gating after the placeholder build.

## 5. Branches, protection and releases

| Branch | Gets | Protection (applied once each check has run once) |
|---|---|---|
| `develop` (default) | feature PRs from worktrees | PR required; required checks `guards`, `docs`, `macos` |
| `staging` | PRs from `develop` | same + `Release / package` green |
| `main` | PRs from `staging`; tags `v*` | same; tags only from `main` (enforced in `release.yml`) |

Release flow: `develop` → PR → `staging` (RC artifact, then manual QA with the E2E suite in `evaluation.md`) → PR → `main` → tag `vX.Y.Z` → draft release → publish by hand. Sparkle appcast generation is added with DD-809 (M2); it hooks into `ci/sign-notarize.sh` after stapling.

### Secrets (Settings ▸ Secrets and variables ▸ Actions)

| Name | Needed for | Status |
|---|---|---|
| `DEVELOPER_ID_P12_BASE64`, `DEVELOPER_ID_P12_PASSWORD`, `DEVELOPER_ID_IDENTITY` | Developer ID signing | **missing**: needs an Apple Developer Program account |
| `NOTARY_APPLE_ID`, `NOTARY_TEAM_ID`, `NOTARY_APP_PASSWORD` | notarization | **missing** |
| variable `LINUX_CORE_REQUIRED` | makes `linux-core` blocking | unset (§4) |

## 5a. Public-repo hardening

The repo may become public once CI is green (user decision 2026-10-15: public only while CI is running, otherwise private; the orchestrator session performs the flip). Rules that hold either way:

- Every workflow sets top-level `permissions: contents: read`; only `release.yml`'s package job widens to `contents: write`, to create the draft release.
- No `pull_request_target`. Fork PRs run on plain `pull_request`, which gets no secrets and a read-only token.
- Signing and notarization secrets are referenced only in the step that runs for `v*` tags, and tags must be on `main`.
- Settings ▸ Actions ▸ General: "Require approval for all outside collaborators" (at least first-time contributors) before fork workflows run.
- Nothing from the reference pack (screenshots, assets, notes) and no absolute home paths or secrets are committed (`organization.md` §2).

## 6. Contracts with the implementer's files

| Contract | Expected |
|---|---|
| `Scripts/make-app.sh` | Reads `CONFIGURATION` (`debug`/`release`, default debug) and `ARCH` (`native`/`universal`); writes `build/Dedock.app` with `LSUIElement = YES` and a valid ad-hoc signature (`codesign --verify --deep --strict` passes). Universal = `swift build -c release --arch arm64 --arch x86_64`. |
| Entitlements | `Sources/Dedock/Dedock.entitlements` or `Scripts/Dedock.entitlements` if hardened-runtime exceptions are needed; picked up by `ci/sign-notarize.sh`. |
| `Scripts/check-deps.sh` | Exits non-zero on a module-rule violation; `guards` runs it when present. |
| Debug-only switches | `DEDOCK_E2E*`, `DEDOCK_FRAME_LOG` honoured only in `app.dedock.Dedock.debug` (see `evaluation.md` App ↔ harness contract). |

## 7. Running it locally

```sh
cd "$DEDOCK_HOME/Dedock app"                          # or a worktree
ci/guards.sh
docker compose -f docker/compose.yml run --rm docs-lint
docker compose -f docker/compose.yml run --rm linux-core
swift build --build-tests && swift test --parallel
ci/build-app.sh debug                                  # build/Dedock.app + zip
```

Docker Desktop must be running for the two compose commands.

## 8. Cost

The repo is private. GitHub bills macOS runner minutes at roughly 10× Linux minutes against the account's monthly quota. Controls: macOS only on PRs into the three long-lived branches, pushes to `staging`/`main` and manual runs; path filters skip docs-only changes; `concurrency` cancels superseded runs; 30 min timeout (45 for release). E2E with computer use stays on the local Mac (it needs a real desktop and TCC grants) and is not part of hosted CI.

## 9. Not in hosted CI (and why)

| Check | Where it runs |
|---|---|
| E2E / UI with computer use, motion measurement, pixel checks | local Mac, testing session, per `evaluation.md` |
| Accessibility / Screen Recording features | local Mac; hosted runners cannot grant TCC |
| Performance budgets (`evaluation.md` L5) | local nightly script once the app has a release build; may move to a self-hosted Mac runner later |
