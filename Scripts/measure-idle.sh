#!/bin/zsh
# Idle CPU, idle wakeups and memory of one process (docs/evaluation.md §6, NFR-1, NFR-2).
# Replaces XCTCPUMetric / XCTMemoryMetric, which need Xcode.
#
#   Scripts/measure-idle.sh <pid|process-name> [seconds=60] [csv-out]
#
# CPU: `top` samples once a second for seconds+1 samples; the first sample is
#      dropped (top's first value is since process start); the rest averaged.
# Wakeups: top's IDLEW is cumulative, so (last - first) / seconds = idle wakeups/s.
#      Gate "no timer faster than 1 Hz" ~ wakeups/s <= 1. powermetrics (sudo) is the
#      confirming method; this one needs no privileges.
# Memory: phys_footprint from `footprint`, RSS from `ps`.
#
# The caller sets up the condition (dock hidden, pointer still, or a SYN loop running).
# Exit status: 0 if CPU < 0.5 % and wakeups <= 1/s, 1 otherwise (gates from NFR-1).
set -euo pipefail

target=${1:?usage: measure-idle.sh <pid|name> [seconds] [csv]}
secs=${2:-60}
csv=${3:-}

if [[ $target == <-> ]]; then pid=$target; else pid=$(pgrep -x $target | head -1); fi
[[ -n ${pid:-} ]] && kill -0 $pid 2>/dev/null || { echo "no such process: $target" >&2; exit 2 }
name=$(ps -o comm= -p $pid | xargs basename)

# DEDOCK_TOP_OVERRIDE=<file>: read top's output from a file (self-test of the fail-closed path).
if [[ -n ${DEDOCK_TOP_OVERRIDE:-} ]]; then raw=$(<$DEDOCK_TOP_OVERRIDE); else raw=$(top -l $((secs + 1)) -s 1 -pid $pid -stats pid,cpu,idlew 2>/dev/null); fi
[[ -n $csv ]] && print -r -- "$raw" > ${csv:r}.top.txt   # keep the raw samples next to the CSV
samples=$(print -r -- "$raw" | awk -v p=$pid '$1 == p { print $2, $3 }')
n=$(print -r -- "$samples" | grep -c . || true)
kill -0 $pid 2>/dev/null || { echo "process $pid exited during the run" >&2; exit 2 }

read cpu_avg cpu_max wps <<<$(print -r -- "$samples" | awk -v s=$secs '
  NR == 1 { w0 = $2; next }
  { sum += $1; n++; if ($1 > max) max = $1; w1 = $2 }
  END { printf "%.3f %.1f %.2f\n", (n ? sum / n : 0), max, (s ? (w1 - w0) / s : 0) }')

fp_mb=$(footprint $pid 2>/dev/null | awk '/Footprint:/ { for (i = 1; i <= NF; i++) if ($i == "Footprint:") { v = $(i+1); u = $(i+2) } }
  END { if (u == "KB") v /= 1024; if (u == "GB") v *= 1024; printf "%.1f", v }')
rss_mb=$(ps -o rss= -p $pid | awk '{ printf "%.1f", $1 / 1024 }')

verdict=PASS
awk -v c=$cpu_avg -v w=$wps 'BEGIN { exit !(c < 0.5 && w <= 1.0) }' || verdict=FAIL
# Fail closed: without (almost) every sample the averages above are made-up zeros.
if (( n < secs - 1 )); then verdict=FAIL; echo "FAIL top gave $n samples for $pid (need >= $((secs - 1)) of $((secs + 1)))"; fi
echo "samples=$n"

stamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
os=$(sw_vers -buildVersion)
echo "process=$name pid=$pid seconds=$secs"
echo "cpu_avg_pct=$cpu_avg cpu_max_pct=$cpu_max (gate < 0.5, target < 0.3)"
echo "idle_wakeups_per_s=$wps (gate <= 1)"
echo "phys_footprint_mb=$fp_mb rss_mb=$rss_mb (NFR-2 gate <= 120 with one Edge Dock)"
echo "verdict=$verdict"

if [[ -n $csv ]]; then
  [[ -f $csv ]] || echo "time,macos_build,process,pid,seconds,cpu_avg_pct,cpu_max_pct,idle_wakeups_per_s,phys_footprint_mb,rss_mb,verdict" > $csv
  echo "$stamp,$os,$name,$pid,$secs,$cpu_avg,$cpu_max,$wps,$fp_mb,$rss_mb,$verdict" >> $csv
fi
[[ $verdict == PASS ]]
