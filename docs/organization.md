# dedock repo organization

How the dedock repository, branches, worktrees, agents and builds are organised. Written 2026-10-15.

---

## 1. Where things live

`$DEDOCK_HOME` is the local project folder that holds the app repo (`Dedock app/`) and the reference pack side by side. Its absolute path is machine-specific and is never written into the repo.

| What | Path | Notes |
|---|---|---|
| Project folder | `$DEDOCK_HOME` | Holds the app repo and the reference pack side by side. |
| **App repo root** | `$DEDOCK_HOME/Dedock app` | Everything that is part of the app (code, scripts, tests, docs) goes inside this folder. Private GitHub repo `luckysharda/dedock` (`origin`). The folder name has a space, so always quote paths. |
| Worktrees | `$DEDOCK_HOME/Dedock app/.worktrees/<name>` | One per branch of work, on a branch named by kind (§4.1). `.worktrees/` is git-ignored. |
| Reference pack (read-only) | `<pack>` | Research material kept outside the repo. Citations of the form `<pack>/dedock-plan/features.md` point into it. Never edited from this repo, never copied into it. |

**`<pack>`** stands for the reference pack folder next to the repo on the developer machine. Its absolute location is never written into the repo.

**Reading order in the pack** (`README.md`, "Start here"): `README.md` → `dedock-plan/` (`features.md` with the Feature-mix matrix, `design-system.md`, `ux-patterns.md`, `architecture.md`, `system-design.md`, `adoption-plan.md`) → `dedock-inputs/animation-spec.md` (resolved motion tokens: use them, do not re-argue them) → `dockdoor/`, `dockdoor-pro/`, `cooldock/` (incl. `how-it-is-built.md`, `layout-modes.md`) → `apple-developer-reference.md` → screenshots.

---

## 2. Hard rules for every person and agent

- **The repo may be public.** No absolute home paths, secrets, tokens or reference-pack material (screenshots, assets, copied notes) are ever committed. Cite the pack by relative name only (`dedock-plan/features.md`).

| Rule | What it means in practice |
|---|---|
| **Notchy is out of scope** | Never open, search, cite or summarise `<pack>/notchy/` or `<pack>/research/notchy-*`. Exclude them from every `grep`/`find` (`--exclude-dir=notchy`, `! -name 'notchy-*'`). Every agent prompt repeats this rule. |
| **Clean-room** (`dedock-plan/adoption-plan.md` §7) | DockDoor is GPL-3.0. Reproduce features and behaviour only, never code. Nobody writing dedock code opens DockDoor's source (or alt-tab-macos, Docky, tungsten-edge, boring.notch, Ice) while working on the matching module. API names, numeric defaults and behaviour descriptions may cross over; code and UI strings may not. Never paste research excerpts into dedock source. Do not read `research/dockdoor-ui-strings.txt` or `research/dockdoor.sdef` while writing strings or the sdef. |
| **Closed references** | CoolDock and DockDoor Pro are closed source. Use only their public descriptions as collected in the pack. No artwork, copy, widget designs or names from them. |
| **Visual design is our own** | Features and behaviour (timings, reveal logic, preview lifecycle) match DockDoor and CoolDock. The look is new and must differ from both. Reference screenshots are for comparison only (`docs/evaluation.md` §9). dedock's tokens live in `docs/design.md` once the user picks a direction. |
| **Names** | "DockDoor", "DockDoor Pro" and "CoolDock" appear only in factual comparison or integration text. Scenario and setting names are our own (`adoption-plan.md` §7.2 item 7). |
| **Native Dock safety** | No code or test writes `com.apple.dock` prefs without the user's explicit consent and a restore path (DD-108). E2E teardown diffs the prefs (`docs/evaluation.md` REG-006). |

---

## 3. Repo layout (SwiftPM first)

Xcode is not installed, so the repo is a Swift package at the root. The module set follows `dedock-plan/architecture.md` §12 (there it sits under `Packages/DedockKit/`; here it moves to the root). The target layout is `docs/plan.md` §1.1 and, per module, `docs/architecture.md` §2–§4; the tree below repeats it with the evaluation tools added. An `.xcodeproj` can be added later if Xcode is installed; logic stays in the package either way.

```text
Dedock app/                          repo root
├── Package.swift                    swift-tools-version 6.x, platforms [.macOS(.v14)], Swift 6 language mode
├── README.md
├── Support/Info.plist               template filled by make-app.sh
├── Sources/
│   ├── Dedock/                      executable: composition root, status item, lifecycle
│   ├── DedockCore/                  IDs, geometry, ScreenEdge, interval maths, clock protocol (no AppKit)
│   ├── DesignSystem/                panel base, materials, tokens from docs/design.md, motion tokens
│   ├── Diagnostics/                 os.Logger categories, signposts, edge trace ring buffer
│   ├── DisplayTopology/             NSScreen → DisplayLayout, screen-change and wake observation
│   ├── SettingsStore/               typed model, layout.json schema + migrations
│   ├── EventTapKit/                 PointerHub only in M1 (event taps later)
│   ├── EdgeDock/                    Trigger/, Reveal/, Panel/, Layout/, Displays/, NativeDock/, Tiles/, Drag/
│   ├── SettingsUI/                  Settings window; Edge Dock pane in M1
│   └── (later) PrivateBridges, Permissions, WindowKit, DockObserver, PreviewUI, Switcher,
│                DedockWidgets, DockLocking, Automation, Updates, ... (architecture.md §4, §4.1)
├── Tests/
│   ├── <Module>Tests/               swift-testing suites, one per library
│   ├── DedockTestSupport/           shared fakes target: TestClock, FakeScreenProvider, FakePointerHub,
│   │                                FakeWorkspace, FakeDockPreferences, FakeLayer
│   └── E2E/<feature>.md             E2E scripts, one per acceptance criterion (docs/evaluation.md §7)
├── Scripts/
│   ├── make-app.sh                  build/Dedock.app, Info.plist, iconutil icon, ad-hoc codesign
│   ├── run.sh                       make-app, quit a running copy, run in the foreground (logs to the terminal)
│   ├── measure-idle.sh              idle CPU / RSS sampler (replaces XCTest metrics)
│   ├── measure-pixels.swift         pixel and edge measurement (docs/evaluation.md §8, §9)
│   ├── check-deps.sh             module layering rules (architecture.md §5)
│   └── check-strings.sh             clean-room string guard (adoption-plan.md §7.2 item 4), from M2
├── Tools/
│   ├── (E2E driver lives in Scripts/e2e/pointer.swift, owned by the E2E lane)
│   └── FixtureHost/                 later: opens N titled windows
├── docs/
│   ├── architecture.md  plan.md  design.md  evaluation.md  organization.md  status.md
│   ├── features/<feature>.md        behaviour spec + "Sources consulted" (plan.md §5 step 2)
│   ├── design/<feature>/            design-sense pages (plan.md §5 step 3)
│   ├── compare/<feature>.md         side-by-side comparison (plan.md §5 step 10)
│   ├── evidence/<feature>/<date>/   cropped captures + measurement CSVs only
│   └── qa-matrix.md                 manual matrix (displays, Dock positions, OS versions)
├── build/                           git-ignored: Dedock.app, e2e/<run>/ recordings and logs
└── .worktrees/                      git-ignored: feature worktrees
```

Libraries are exposed as one library product per module (the "DedockKit" set). Dependency direction follows `dedock-plan/architecture.md` §5: `DedockCore` depends on nothing in the repo; feature modules depend on `DedockCore`, `DesignSystem`, `Diagnostics` and `SettingsStore` through protocols; only the `Dedock` executable's composition root sees every module.

**State on 2026-10-15.** A first skeleton is in WIP commit `bb9faf3` on `feature/edge-dock-reveal`: `Package.swift` with `DedockCore`, `EdgeDock`, the `Dedock` executable and two test targets (`DedockCoreTests`, `EdgeDockTests`); sources under `Sources/DedockCore`, `Sources/EdgeDock/Trigger`, `Sources/EdgeDock/Reveal` and `Sources/Dedock`. `Scripts/` and `Tools/` do not exist yet. The earlier stray `preflight.swift` probe is gone from the worktree root.

---

## 4. Branch model and worktrees

| Branch | Purpose | Receives from | Rules |
|---|---|---|---|
| `main` | released builds | `staging` (merge + tag `vX.Y.Z`), `hotfix/*` | no direct commits |
| `staging` | release candidates | `develop` | full regression list (`docs/evaluation.md` §5) before the merge |
| `develop` | integration | `feature/*`, `fix/*`, `test/*`, `ci/*`, `docs/*` via PR | every PR green on CI |
| `<kind>/<name>` (§4.1) | one piece of work | branched from `develop` | lives in `.worktrees/<name>`; one owner lane |
| `hotfix/<name>` | urgent fix to a release | branched from `main` | merged to `main`, then back into `develop` |

Create, list and remove a feature worktree (run from the repo root):

```sh
cd "$DEDOCK_HOME/Dedock app"
git fetch origin
git worktree add ".worktrees/<feature>" -b "feature/<feature>" origin/develop
git -C ".worktrees/<feature>" push -u origin "feature/<feature>"
git worktree list
# after the PR is merged:
git worktree remove ".worktrees/<feature>"
git branch -d "feature/<feature>"
```

### 4.1 Branch kinds

| Prefix | Use | Example |
|---|---|---|
| `feature/` | an app feature only (a DD id ships) | `feature/edge-dock-reveal` |
| `fix/` | bug fixes, each with a REG id and a `.regression` test (`evaluation.md` §5.1) | `fix/review-followups` |
| `test/` | test tooling: E2E harness, fixtures, measurement scripts | `test/e2e-harness` |
| `ci/` | pipelines, Docker, repo guards | `ci/regression-step` |
| `docs/` | docs-only changes | `docs/arch-reconcile` |

Renaming an open PR's branch closes the PR on GitHub, so an existing branch keeps its name until it merges; new work uses these prefixes.

The repo-root checkout stays on `develop` and is not used for feature work. Current worktree: `.worktrees/edge-dock-reveal` on `feature/edge-dock-reveal`.

---

## 5. Commits and pull requests

**Commit messages.** `<type>(<scope>): <summary>`, summary in the imperative, ≤ 72 characters.

| Part | Values |
|---|---|
| type | `feat`, `fix`, `test`, `docs`, `refactor`, `perf`, `build`, `chore` |
| scope | module (`EdgeDock`, `SettingsStore`) or area (`docs`, `scripts`) |
| body | what and why; the DD IDs it implements (`Implements DD-912, DD-928`) |
| trailer | commits made by Claude end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` |

Example: `feat(EdgeDock): reverse in place from the presentation value` with body `Implements DD-928.`

Commit only when asked or when the lane's brief says so. Never commit `build/`, recordings or full-desktop screenshots.

**Pull requests** go from `feature/<feature>` into `develop`. Title: `[DD-xxx, …] <short title>`. Description sections:

1. **Summary**: what changed, in a few lines.
2. **Features**: DD IDs with links to `dedock-plan/features.md` rows.
3. **Evaluation**: the filled scorecard (`docs/evaluation.md` §10), commands run, E2E run IDs, perf numbers.
4. **Sources consulted** (clean-room, `adoption-plan.md` §7.2 item 5): pack sections, Apple docs, MIT projects. A PR whose author read GPL source for that module is rejected.
5. **Evidence**: cropped captures and CSVs under `docs/evidence/`.
6. **Checklist**: `[ ] swift build`, `[ ] swift test`, `[ ] Scripts/make-app.sh`, `[ ] regression list updated`, `[ ] docs/status.md updated`.

PRs created by Claude end with the Claude Code attribution line given in the session's attribution reminder. Merge with squash into `develop`; `develop` → `staging` and `staging` → `main` use merge commits.

---

## 6. Sub-agent lanes

Work is fanned out to sub-agents in lanes. The lead session owns the plan, hands out briefs, and merges results. Each feature moves through the 12 steps in `docs/plan.md` §5 (worktree → research → four design senses → user pick → `docs/design.md` → implement → unit tests → E2E → regression → comparison → PR → promote); the lanes below map onto those steps.

| Lane | Does | May write | May not |
|---|---|---|---|
| **Research** | reads the pack, Apple docs (`apple-developer-reference.md`), the web; answers specific questions | nothing in the repo; returns findings as its final message | write code; read GPL source for a module someone is implementing; touch the desktop |
| **Docs** | writes and updates `docs/*.md` in one worktree | `docs/` in its assigned worktree | write code; touch the desktop |
| **Design** | the design senses for a feature and, after the user's pick, the tokens in `docs/design.md` (`docs/plan.md` §5 steps 3–5) | `docs/design/<feature>/`, `docs/design.md` | reuse reference artwork, shapes or colour schemes; pick a direction for the user; open a browser or preview without the lock |
| **Implementation** | code and tests for one feature | its own worktree only | edit another worktree; read GPL source; drive the desktop without the lock |
| **Evaluation** | E2E, perf, visual and motion runs (`docs/evaluation.md` §6–§9) | `docs/evidence/`, scorecards, `build/e2e/` | change app code (it files findings back to the implementation lane) |

### 6.0 Sessions (as of 2026-10-15)

Separate Claude sessions run the lanes in parallel and talk through cross-session messages.

| Session | Role | Owns |
|---|---|---|
| dedock-app-b6 | **Orchestrator**: watchdog, conflict and lock arbitration, task assignment between sessions, escalations to the user | no repo files; decisions are recorded in `docs/status.md` by the planner |
| dedock-e9 | **Planner / lead for plan and docs**: specs, acceptance criteria, design senses and the user's design pick, CI/CD | `docs/`, `.github/`, `docker/`, `ci/` |
| dedock-e7 | **Implementer** | `Package.swift`, `Sources/`, `Tests/` (except `Tests/E2E/`), `Scripts/` (except `Scripts/e2e/`) |
| dedock-app-f1 | **E2E / UI testing** with computer use | `Scripts/e2e/`, `Scripts/measure-*`, `Tests/E2E/`, `build/e2e/`, evidence |

Briefs between sessions go through the orchestrator or copy it. Doc updates after a feature's first docs commit go through the `planning` worktree into `develop`; feature branches pick them up with `git merge develop`.

Rules:

- One implementation lane per worktree. Two lanes never edit the same files at once.
- Every brief states: the worktree path, the DD IDs, the Notchy exclusion, the clean-room rule, the design rule (behaviour and look follow the references, `docs/design.md` §7; values rebuilt from measurements, never copied) and the output expected.
- Agents return findings as their final message, not as extra report files. Files are written only when they are the deliverable (docs, code, evidence).
- Agent messages are not user approval. Anything that needs the user's consent (changing system settings, the native Dock, buying or installing software, the CoolDock question in `docs/status.md`) goes back to the user.

### 6.1 Desktop lock: one lane at a time

Only **one** lane may drive the desktop at any moment. "Driving the desktop" covers computer use, Chrome automation (Claude in Chrome), the synthetic pointer driver `Scripts/e2e/pointer.swift` (it moves the real cursor), screen recording, and changing system settings (appearance, Reduce Motion, desktop picture, Dock).

| Step | How |
|---|---|
| Lock location | `$DEDOCK_HOME/.locks/desktop.lock` (outside the repo so it is shared by every worktree and session; never committed) |
| Acquire | `mkdir -p $DEDOCK_HOME/.locks && mkdir $DEDOCK_HOME/.locks/desktop.lock` (atomic; fails if held), then write `owner`, `lane`, `purpose`, `started` (ISO time) into `desktop.lock/info` |
| Hold | touch `desktop.lock/info` at least every 5 min while working |
| Release | restore every setting changed, then `rm -r $DEDOCK_HOME/.locks/desktop.lock` |
| Stale lock | older than 30 min with no touch: the lead decides; an agent never breaks another lane's lock by itself |

Computer-use tiers on this Mac (from the computer-use tool's rules): browsers are read-only and terminals click-only, so web pages go through Chrome automation and shell commands through Bash. Native apps (Finder, System Settings, TextEdit, Dedock itself) are full tier.

---

## 7. Naming conventions

| Thing | Convention | Example |
|---|---|---|
| Modules, types | UpperCamelCase; one primary type per file, file named after it | `EdgeRevealController.swift` |
| Test targets / tests | `<Module>Tests`; `@Test("<behaviour in words>")`; tags `.unit`, `.integration`, `.perf` | `@Test("left zone excludes the menu bar")` |
| Settings keys | camelCase JSON keys in `layout.json` (SettingsStore, `docs/architecture.md` §7; no `UserDefaults` in M1). Logical names follow `dedock-plan/features.md` §0.2 | `dock[i].showDelay` → `docks[i].reveal.showDwellMs` |
| Bundle IDs | `app.dedock.Dedock` (release), `app.dedock.Dedock.debug` (debug) | — |
| Logging | subsystem `app.dedock.Dedock`; categories from `dedock-plan/system-design.md` §10 (`edge`, `dock`, `layout`, …) | — |
| Signposts / timing events | names match the budget rows in `system-design.md` §9 | `edge.evaluate`, `reveal.begin`, `launch.edgeReady` |
| Motion tokens | `dd.motion.*` in code and `docs/design.md` §3; same values as `motion.*` in `dedock-inputs/animation-spec.md` §2 | `dd.motion.edge.reveal` = `motion.edge.reveal` |
| Branches and worktrees | `<kind>/<kebab-case>` with kind from §4.1; worktree folder = the part after the slash | `feature/edge-dock-reveal` → `.worktrees/edge-dock-reveal`; `test/e2e-harness` → `.worktrees/e2e-harness` |
| Milestones | M1–M18 are this repo's own (`docs/plan.md` §4.1; M1 = Edge Dock reveal). The reference pack's roadmap milestones are written AP-M0…AP-M14 (`adoption-plan.md` §10) | M1 ⊂ AP-M3 |
| Test and evidence IDs | E2E `E2E-L-<nn>` and `E2E-R-<nn>`, regression `REG-<nnn>`, M1 tasks `T0`–`T23` (`docs/plan.md` §6.1), evidence `docs/evidence/<feature>/<YYYY-MM-DD>/` | `E2E-L-06` |

---

## 8. Build, run and test

Toolchain: Command Line Tools with Swift 6.4. `swift build` and `swift test` (swift-testing) work. XCTest, XCUITest, `xcodebuild` and Instruments (`xctrace`) do not.

| Command | What it does |
|---|---|
| `swift build` | debug build of all targets |
| `swift test` | unit + integration tests (fakes only, no desktop) |
| `swift test --filter EdgeDockTests` | one test target |
| `swift test -c release --filter EdgeDockPerf` | release-mode micro-benchmarks (`docs/evaluation.md` §6) |
| `Scripts/make-app.sh [debug\|release]` | builds the `Dedock` product and assembles `build/Dedock.app` |
| `Scripts/run.sh` | runs `make-app.sh debug`, quits a running Dedock, runs `build/Dedock.app/Contents/MacOS/Dedock` in the foreground so environment switches (`DEDOCK_E2E=1`, `DEDOCK_FRAME_LOG=1`) reach it and logs stream to the terminal (`docs/architecture.md` §5); `log stream --level debug --predicate 'subsystem == "app.dedock.Dedock"'` captures them to a file for E2E |

`Scripts/make-app.sh` contract (to be written in M1):

1. `swift build -c <config> --product Dedock`.
2. Create `build/Dedock.app/Contents/{MacOS,Resources}`; copy the binary to `Contents/MacOS/Dedock`.
3. Write `Contents/Info.plist`: `CFBundleIdentifier` = `app.dedock.Dedock.debug` (debug), `CFBundleExecutable` = `Dedock`, `CFBundlePackageType` = `APPL`, `LSUIElement` = YES, `LSMinimumSystemVersion` = 14.0, version from `git describe`.
4. Sign: `codesign --force --sign "${DEDOCK_SIGN_IDENTITY:--}" build/Dedock.app` (ad-hoc by default).

**Signing.** No code-signing identity exists on this Mac. Ad-hoc signing is enough for the Edge Dock: edge sensing uses global `NSEvent` monitors, which need no permission (`dedock-plan/system-design.md` §5.3). Accessibility and Screen Recording grants are tied to the code signature, and an ad-hoc signature changes with every build, so before the DockDoor-class features a stable self-signed identity (for example "Dedock Dev" in the login keychain) must be created and passed through `DEDOCK_SIGN_IDENTITY`. Developer ID signing and notarization come with release work (`dedock-plan/architecture.md` §13).
