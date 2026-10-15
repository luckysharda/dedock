## What
<!-- Feature / DD ids, one paragraph. -->

## Sources consulted (clean-room)
<!-- Reference files read (<pack>/...). No DockDoor (GPL) code copied, translated or paraphrased. -->

## Checks
- [ ] `swift build` and `swift test` pass locally
- [ ] `docker compose -f docker/compose.yml run --rm linux-core` (once Linux gating lands)
- [ ] E2E scenarios in docs/evaluation.md run (link the run log / screenshots)
- [ ] App PRs: E2E `Scripts/e2e/regress.sh` scorecard attached (link or paste the summary)
- [ ] New bug fixed → new REG id in `Tests/E2E/regressions.md` + a `.regression` unit test in the same commit
- [ ] docs/status.md updated
- [ ] No Notchy code, assets or references
