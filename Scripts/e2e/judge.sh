#!/bin/zsh
# Judges one scenario directory written by scenario.sh: report.txt (gates + "VERDICT ...") and
# metrics.jsonl. Works on saved files only, so analyzer changes can re-score old runs
# (Scripts/e2e/regress.sh rescore) without another desktop session.
#
#   Scripts/e2e/judge.sh <scenario-dir>      exit 0 PASS, 1 FAIL, 3 VOID (real input got in: rerun)
set -uo pipefail

B=${0:A:h:h:h}/build/e2e
O=${1:?usage: judge.sh <scenario-dir>}
[[ -f $O/params.env ]] || { echo "no params.env in $O" >&2; exit 2 }
for kv in $(<$O/params.env); do typeset "p_${kv%%=*}=${kv#*=}"; done
scn=$p_scn edge=$p_edge show=$p_show hide=$p_hide n=$p_n run=$p_run

M=$O/metrics.jsonl; rm -f $M
# Fail closed: analyze exits 0 (gates pass) or 1 (a gate failed); anything else means it did not
# judge at all (missing log, crash), which must never read as PASS.
ok_rc() { (( $2 == 0 || $2 == 1 )) || echo "FAIL tool analyze $1 exited $2: not judged" }
{
  echo "== $scn $edge ($run) judged $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  [[ -s $O/slice.txt ]] && cat $O/slice.txt
  $B/analyze contamination $O/listen.txt metrics=$M; ok_rc contamination $?
  case $scn in
    x-01|x-02|x-03|x-04) $B/analyze timing $O/log.ndjson show=$show hide=$hide metrics=$M; ok_rc timing $?
      # With DEDOCK_FRAME_LOG on, the same trials also give the motion numbers (§8).
      grep -q '"eventMessage":"frame ' $O/log.ndjson && { $B/analyze frames $O/log.ndjson metrics=$M; ok_rc frames $? }
      # REG-020: the driver jumps ~150 pt into the edge in ONE event; that entry delta must not
      # count as push-through, so a clean x-01 reveals by dwell only.
      if [[ $scn == x-01 ]]; then
        np=$(grep -cE '"eventMessage":"reveal.transition[^"]*cause=push' $O/log.ndjson || true)
        (( np == 0 )) && echo "PASS REG-020 no push-through from a single jump into the edge" || echo "FAIL REG-020 $np reveal(s) by push in x-01 (entry delta counted as push?)"
      fi ;;
    x-05a|x-05b|x-06) $B/analyze timing $O/log.ndjson show=$show hide=$hide metrics=$M; ok_rc timing $?; $B/analyze frames $O/log.ndjson metrics=$M; ok_rc frames $?
      # A reversal scenario in which nothing reversed tested nothing: fail it explicitly.
      case $scn in
        x-05a) pat='"eventMessage":"reveal.transition[^"]*from=hiding to=revealing'; need=$n ;;
        x-05b) pat='"eventMessage":"reveal.transition[^"]*from=revealing to=hiding'; need=$n ;;
        x-06)  pat='"eventMessage":"reveal.transition[^"]*from=(hiding to=revealing|revealing to=hiding)'; need=1 ;;
      esac
      got=$(grep -cE "$pat" $O/log.ndjson || true)
      if (( got >= need )); then echo "PASS reversals occurred: $got (need ≥ $need)"; else echo "FAIL expected reversals: $got occurred (need ≥ $need); the scenario did not exercise reverse-in-place"; fi ;;
    perf-move) cat $O/perf.txt ;;
  esac
} > $O/report.raw.txt
# Verdict: VOID if real input got in (rerun; not an app result), else FAIL on any failed gate.
# Fail closed: a scenario with no gate evaluated besides contamination tested nothing.
grep -vq '^PASS input contamination' <(grep '^PASS' $O/report.raw.txt) || echo "FAIL no gate was evaluated" >> $O/report.raw.txt
if grep -q '^FAIL input contamination' $O/report.raw.txt; then verdict=VOID
elif grep -q '^FAIL' $O/report.raw.txt; then verdict=FAIL
else verdict=PASS; fi
{ cat $O/report.raw.txt; echo "VERDICT $verdict $scn $edge"; } > $O/report.txt
cat $O/report.txt
rm $O/report.raw.txt
case $verdict in PASS) exit 0 ;; FAIL) exit 1 ;; VOID) exit 3 ;; esac
