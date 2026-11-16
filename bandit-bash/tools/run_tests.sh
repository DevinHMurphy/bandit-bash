#!/bin/sh
# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_tests.sh
# Author:
# Created:  October 29, 2026
# Modified: November 16, 2026
# ==============================================================================
# Runs the headless test suites, parse checks and a launch check, and prints one verdict line per
# run, so a result reads in a few lines instead of the full Godot output. Works from any folder.
#
#   tools/run_tests.sh                       every suite, then a headless launch
#   tools/run_tests.sh map enemies ui/input  only these suites (no launch); a top folder with
#                                            parts, such as enemies or ui, runs all its parts
#   tools/run_tests.sh --open ...            also opens the live report in the browser
#   tools/run_tests.sh --check <git ref>     parse-check every .gd changed since <git ref>
#   tools/run_tests.sh --check-file res://scripts/a.gd ...
#
# Suites are found, not listed: every tests/<name>/run_all.gd is a suite named <name>, and a
# folder without one may hold suites a level down, tests/<name>/<part>/run_all.gd, named
# <name>/<part> (tests/ui and tests/enemies keep the cases their parts share at the top). Each
# must print a summary line "--- N passed, M failed ---" (", K skipped" may follow), and should
# declare a one-line const SUITE_DESCRIPTION for the report and time its test groups with
# tests/group_clock.gd. A tests/ folder with no suite at either level is named in a note and not run.
#
# Suites run in parallel, at most JOBS Godot processes at once (default: the machine's core count;
# JOBS=1 runs them one after another, in the order found). Verdicts print once every suite has
# finished, always in the order found.
#
# The report: a suite run writes report.html in the log folder and rewrites it about every 2 s
# while suites run (tools/test_report.awk; the page reloads itself until the run ends). It opens in
# the browser only with --open, which tools/run_tests.cmd passes; otherwise its path prints beside
# the logs'. Each suite's time is compared with its last PASS on this machine, from a history file
# outside the checkout: $BANDIT_TEST_HISTORY if set, else BanditBash/tests/history.tsv under
# %LOCALAPPDATA% on Windows, bandit_bash/tests/ under $XDG_STATE_HOME on Linux, BanditBash/tests/
# under ~/Library/Application Support on macOS. It keeps the last HISTORY_RUNS runs.
#
# Test user folders: each suite's Godot gets its own user://, so no two suites, in this run or any
# other, ever share one. The runner points the variable Godot builds user:// from (APPDATA on
# Windows, XDG_DATA_HOME on Linux, HOME on macOS) at bandit_bash_tests_<suite> in the run's log
# folder, for that one process; nothing is written to the checkout. The suites' guards
# (tests/ui/ui_suite.gd, tests/sessions/sessions_case_base.gd) look for that name on the user
# folder's path and skip their save cases without it, so a skip that says "needs a test user
# folder" fails the suite: here it can only mean the route broke. When a run ends, a suite that
# passed keeps only its Godot logs (user_logs/<suite>/ in the log folder); a FAIL or HUNG suite
# keeps its whole folder, whose path prints under its verdict. An interrupted run keeps the logs.
#
# Verdicts: PASS; FAIL (a failed test, a script or parse error, a leak, no summary line, or no
# test user folder); EXIT-CRASH (every test passed but the engine crashed at exit, Godot issue
# #117975: the results stand); HUNG (the run outlived SUITE_TIMEOUT seconds, default 300, and was
# stopped: a script that fails to compile can leave Godot waiting forever; 0 turns the limit off).
# The exit status is 0 only when nothing failed. Each run's full output is kept in the log folder
# printed at the end. The limit needs `timeout` (coreutils, Git Bash); without it runs are
# unlimited. The import, the parse checks and the launch run as a player would, in the real user
# folder.
#
# Godot: $GODOT if set, else `godot` or `godot4` on PATH, else the project's Windows install.
# ==============================================================================

RUN_START=$(date +%s)
RUN_ID="$RUN_START-$$"
STARTED_TEXT=$(date '+%Y-%m-%d %H:%M:%S')
PROJECT="$(cd "$(dirname "$0")/.." && pwd)"
WINDOWS_GODOT="/c/Users/demur/Documents/Godot/Godot_v4.7.1-stable_win64_console.exe"
LOGS="$(mktemp -d "${TMPDIR:-/tmp}/bandit_tests.XXXXXX")"
# The suites' guards accept a user folder only with a folder of this name on its path
# (tests/ui/ui_suite.gd, tests/sessions/sessions_case_base.gd), so it must stay in step with them.
TEST_DIR_PREFIX="bandit_bash_tests_"
# What the guarded cases print when they skip for want of a test user folder (the same files).
NO_USER_FOLDER='needs a test user folder'
# The launch check's line in the report (suites declare theirs in their run_all.gd).
LAUNCH_DESCRIPTION="The game started headless for 60 frames, with no error or warning"
# Runs the history file keeps; older ones are dropped as a run is added.
HISTORY_RUNS=50
failed=0
status=""
open_report=0
REPORT=""

# --open may come anywhere; the rest keep their order.
for arg in "$@"; do
	shift
	if [ "$arg" = --open ]; then
		open_report=1
	else
		set -- "$@" "$arg"
	fi
done

if [ -z "$GODOT" ]; then
	GODOT="$(command -v godot || command -v godot4 || echo "$WINDOWS_GODOT")"
fi
if ! "$GODOT" --version >/dev/null 2>&1; then
	echo "Godot not found: set GODOT to the Godot 4.7.1 binary."
	exit 2
fi

# The variable Godot's OS::get_data_path() reads, which user:// sits under, and how a path is
# written for it. Checked on Windows only.
case "$(uname -s)" in
MINGW* | MSYS* | CYGWIN*)
	USER_VAR=APPDATA
	;;
Darwin)
	# ASSUMPTION: unchecked on macOS: Godot builds user:// under $HOME/Library/Application Support.
	USER_VAR=HOME
	;;
*)
	# ASSUMPTION: unchecked on Linux: Godot builds user:// under an absolute $XDG_DATA_HOME.
	USER_VAR=XDG_DATA_HOME
	;;
esac

# Every Godot run goes through $LIMIT, so a hung run is stopped instead of blocking the rest.
SUITE_TIMEOUT="${SUITE_TIMEOUT:-300}"
LIMIT=""
if [ "$SUITE_TIMEOUT" -gt 0 ]; then
	if command -v timeout >/dev/null 2>&1; then
		LIMIT="timeout -k 10 $SUITE_TIMEOUT"
	else
		echo "note: no timeout command, so runs have no time limit"
	fi
fi

JOBS="${JOBS:-$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}"
case "$JOBS" in
'' | *[!0-9]* | 0)
	echo "JOBS must be a whole number of at least 1, not '$JOBS'."
	exit 2
	;;
esac

# Output lines that mean a run is broken, whatever its exit code says.
BROKEN='SCRIPT ERROR|Parse Error|Compile Error|Failed to load script|leaked at exit|resources still in use'

# The name column's width: the longest suite name, at least 10, so the verdicts line up.
WIDTH=10

# Judges a finished suite, leaving its verdict in $status and its summary line in $summary: $1
# exit code, $2 log file. The report shows this verdict; it never judges on its own.
judge() {
	summary=$(grep -E '^--- [0-9]+ passed' "$2" | tail -1)
	broken=$(grep -cE "$BROKEN|$NO_USER_FOLDER" "$2")
	fails=$(echo "$summary" | sed -nE 's/.* ([0-9]+) failed.*/\1/p')
	if [ "$1" -eq 124 ] || [ "$1" -eq 137 ]; then
		status=HUNG
	elif [ -z "$summary" ] || [ "$broken" -gt 0 ] || [ "${fails:-1}" -ne 0 ]; then
		status=FAIL
	elif [ "$1" -ne 0 ]; then
		status=EXIT-CRASH
	else
		status=PASS
	fi
}

# Prints one verdict line for a finished suite and leaves it in $status: $1 name, $2 exit code,
# $3 log file.
verdict() {
	judge "$2" "$3"
	printf "%-${WIDTH}s %-10s %s (exit %s)\n" "$1" "$status" "${summary:-no summary line}" "$2"
	if [ "$status" = FAIL ] || [ "$status" = HUNG ]; then
		failed=1
		grep -E "^FAIL|$BROKEN|$NO_USER_FOLDER" "$3" | head -15 | sed 's/^/    /'
	fi
}

# A suite's file name: its name with an underscore for a nested suite's slash.
suite_file_name() {
	echo "$1" | tr '/' '_'
}

suite_log() {
	echo "$LOGS/$(suite_file_name "$1").log"
}

# The folder a suite's Godot builds its user:// under, inside the log folder.
suite_user_root() {
	echo "$LOGS/$TEST_DIR_PREFIX$(suite_file_name "$1")"
}

# A path as Godot reads it from the environment: a Windows path under Git Bash.
native_path() {
	if [ "$USER_VAR" = APPDATA ] && command -v cygpath >/dev/null 2>&1; then
		cygpath -w "$1"
	else
		echo "$1"
	fi
}

# Prints the suites in tests/<name>: the folder itself when it has a run_all.gd, else each part
# a level down that does. Prints nothing when there are none.
suites_in() {
	if [ -f "$PROJECT/tests/$1/run_all.gd" ]; then
		echo "$1"
		return 0
	fi
	for part in "$PROJECT/tests/$1"/*/; do
		if [ -f "$part/run_all.gd" ]; then
			echo "$1/$(basename "$part")"
		fi
	done
}

# Runs one suite in its own test user folder, leaving its start and end times and exit code beside
# its log, and its process id for cancel_run. The end time is written before the code, so the
# report never sees a code without one.
run_suite() {
	suite_file=$(suite_log "$1")
	user_root=$(suite_user_root "$1")
	mkdir -p "$user_root"
	date +%s >"$suite_file.start"
	env "$USER_VAR=$(native_path "$user_root")" $LIMIT "$GODOT" --headless --path "$PROJECT" \
		--script "res://tests/$1/run_all.gd" >"$suite_file" 2>&1 &
	echo $! >"$suite_file.pid"
	wait $!
	code=$?
	date +%s >"$suite_file.end"
	echo $code >"$suite_file.code"
}

# Runs, in order, each suite given that no other worker has taken. mkdir either creates the claim
# or fails, even when two workers try at once, so every suite runs exactly once.
run_unclaimed() {
	for unclaimed in "$@"; do
		if mkdir "$(suite_log "$unclaimed").claim" 2>/dev/null; then
			run_suite "$unclaimed"
		fi
	done
}

# Whether any worker is still running.
workers_running() {
	for worker in $workers; do
		kill -0 "$worker" 2>/dev/null && return 0
	done
	return 1
}

# Judges each suite that finished since the last call, writing its verdict beside its log for the
# report. Loops over $stems, worked out once, since a fork per suite per tick is slow on Windows.
judge_finished() {
	for stem in $stems; do
		log="$LOGS/$stem.log"
		if [ -f "$log.code" ] && [ ! -f "$log.status" ]; then
			judge "$(cat "$log.code")" "$log"
			echo "$status" >"$log.status"
		fi
	done
}

# Where this machine's run history lives, outside every checkout (see the header).
history_path() {
	if [ -n "$BANDIT_TEST_HISTORY" ]; then
		path="$BANDIT_TEST_HISTORY"
	else
		case "$(uname -s)" in
		MINGW* | MSYS* | CYGWIN*)
			path="${LOCALAPPDATA:-$HOME/AppData/Local}/BanditBash/tests/history.tsv"
			;;
		Darwin)
			path="$HOME/Library/Application Support/BanditBash/tests/history.tsv"
			;;
		*)
			path="${XDG_STATE_HOME:-$HOME/.local/state}/bandit_bash/tests/history.tsv"
			;;
		esac
	fi
	if command -v cygpath >/dev/null 2>&1; then
		cygpath -u "$path"
	else
		echo "$path"
	fi
}

# Lists the report's rows in suites.tsv: each suite's name, file stem and description, then the
# launch when it runs.
write_suite_list() {
	: >"$LOGS/suites.tsv"
	for suite in $suites; do
		about=$(sed -nE 's/^const SUITE_DESCRIPTION: String = "(.*)"$/\1/p' \
			"$PROJECT/tests/$suite/run_all.gd" | head -1)
		printf '%s\t%s\t%s\n' "$suite" "$(suite_file_name "$suite")" "$about" >>"$LOGS/suites.tsv"
	done
	if [ "$run_launch" -eq 1 ]; then
		printf 'launch\tlaunch\t%s\n' "$LAUNCH_DESCRIPTION" >>"$LOGS/suites.tsv"
	fi
}

# Writes the report for $1, the run's phase (running, done or interrupted), and swaps it in whole.
# The done phase also leaves this run's history rows in history_rows.tsv.
write_report() {
	[ -n "$REPORT" ] || return 0
	rows_out=""
	if [ "$1" = done ]; then
		rows_out="$LOGS/history_rows.tsv"
	fi
	awk -v logs="$LOGS" -v now="$(date +%s)" -v started="$RUN_START" \
		-v started_text="$STARTED_TEXT" -v phase="$1" -v history="$HISTORY" -v run_id="$RUN_ID" \
		-v full="$run_launch" -v broken="$BROKEN|$NO_USER_FOLDER" -v rows_out="$rows_out" \
		-v iso="$STARTED_TEXT" -f "$PROJECT/tools/test_report.awk" "$LOGS/suites.tsv" \
		>"$REPORT.tmp" 2>"$LOGS/report.err" && mv -f "$REPORT.tmp" "$REPORT"
}

# Adds this run's rows to the history and keeps only the last HISTORY_RUNS runs. A missing or
# unwritable history only loses the comparison, never the run.
record_history() {
	new_rows="$LOGS/history_rows.tsv"
	[ -s "$new_rows" ] || return 0
	mkdir -p "$(dirname "$HISTORY")" 2>/dev/null || return 0
	cat "$new_rows" >>"$HISTORY" 2>/dev/null || return 0
	awk -F '\t' -v keep="$HISTORY_RUNS" '
		NR == FNR { if (!($1 in at)) { at[$1] = ++runs } next }
		at[$1] > runs - keep
	' "$HISTORY" "$HISTORY" >"$HISTORY.tmp" && mv -f "$HISTORY.tmp" "$HISTORY"
}

# Opens the report in the default browser, without waiting for it.
open_in_browser() {
	case "$(uname -s)" in
	MINGW* | MSYS* | CYGWIN*)
		cmd.exe //c start "" "$(cygpath -w "$REPORT")"
		;;
	Darwin)
		open "$REPORT"
		;;
	*)
		xdg-open "$REPORT"
		;;
	esac >/dev/null 2>&1 &
}

# On Ctrl+C or kill: stops the workers, so nothing new starts, then the running suites, and ends
# the run only once they are told to stop. The report shows the run as interrupted.
cancel_run() {
	# shellcheck disable=SC2086
	kill $workers 2>/dev/null
	for pid_file in "$LOGS"/*.pid; do
		[ -f "$pid_file" ] && kill "$(cat "$pid_file")" 2>/dev/null
	done
	judge_finished
	write_report interrupted
	end_run
	exit 130
}

# Deletes a suite's test user folder, after copying its Godot logs to user_logs/<suite>/. Deletes
# only a folder in the log folder whose name has the test prefix. A Godot just stopped on Windows
# can hold files open for a moment, hence the retries.
remove_user_folder() {
	root="$1"
	case "$(basename "$root")" in
	"$TEST_DIR_PREFIX"?*) ;;
	*) return 0 ;;
	esac
	if [ "$(dirname "$root")" != "$LOGS" ] || [ ! -d "$root" ]; then
		return 0
	fi
	kept="$LOGS/user_logs/$(basename "$root" | sed "s/^$TEST_DIR_PREFIX//")"
	logs_dir=$(find "$root" -type d -name logs 2>/dev/null | head -1)
	if [ -n "$logs_dir" ] && [ ! -e "$kept" ]; then
		mkdir -p "$LOGS/user_logs"
		cp -R "$logs_dir" "$kept" 2>/dev/null
	fi
	for _attempt in 1 2 3 4 5; do
		rm -rf "$root" 2>/dev/null
		[ -d "$root" ] || return 0
		sleep 1
	done
	echo "warning: could not delete the test user folder $root; delete it by hand."
}

# Deletes every test user folder still in the log folder except the ones kept for reading.
# Safe to call more than once.
end_run() {
	for root in "$LOGS/$TEST_DIR_PREFIX"*; do
		[ -d "$root" ] || continue
		case " $keep " in
		*" $root "*) continue ;;
		esac
		remove_user_folder "$root"
	done
}

# Parse-checks each res:// script given. The output decides: a crash at exit returns 139 even
# when the check itself was fine.
check_scripts() {
	for script in "$@"; do
		log="$LOGS/check_$(basename "$script").log"
		$LIMIT "$GODOT" --headless --path "$PROJECT" --check-only --script "$script" >"$log" 2>&1
		code=$?
		if grep -qE "$BROKEN|^ERROR:" "$log"; then
			printf "%-${WIDTH}s %-10s %s (exit %s)\n" check FAIL "$script" "$code"
			grep -E "$BROKEN|^ERROR:" "$log" | head -8 | sed 's/^/    /'
			if grep -q 'Identifier not found' "$log"; then
				echo "    (--check-only loads no autoloads: if this names one, cover the script with a suite)"
			fi
			failed=1
		else
			printf "%-${WIDTH}s %-10s %s (exit %s)\n" check PASS "$script" "$code"
		fi
	done
}

$LIMIT "$GODOT" --headless --path "$PROJECT" --import >"$LOGS/import.log" 2>&1

case "$1" in
--check)
	base="${2:?--check needs a git ref}"
	files=$(git -C "$PROJECT" diff --name-only --relative --diff-filter=AMR "$base" -- '*.gd' |
		sed 's|^|res://|')
	if [ -z "$files" ]; then
		echo "No changed .gd files since $base."
		exit 0
	fi
	# Word splitting is wanted: res:// paths have no spaces.
	# shellcheck disable=SC2086
	check_scripts $files
	echo "Logs: $LOGS"
	exit $failed
	;;
--check-file)
	shift
	check_scripts "$@"
	echo "Logs: $LOGS"
	exit $failed
	;;
esac

suites=""
if [ $# -gt 0 ]; then
	for name in "$@"; do
		found=$(suites_in "$name")
		if [ -z "$found" ]; then
			echo "No suite at tests/$name: it needs a run_all.gd there or a level down."
			exit 2
		fi
		suites="$suites $found"
	done
	run_launch=0
else
	for folder in "$PROJECT"/tests/*/; do
		name=$(basename "$folder")
		found=$(suites_in "$name")
		if [ -n "$found" ]; then
			suites="$suites $found"
		else
			echo "note: tests/$name has no run_all.gd, so it is not a suite and was not run"
		fi
	done
	run_launch=1
fi
# Word splitting is wanted: suite names have no spaces, and suites_in prints one per line.
# shellcheck disable=SC2086
suites=$(echo $suites)
# shellcheck disable=SC2086
stems=$(echo $suites | tr '/' '_')
for suite in $suites; do
	if [ ${#suite} -gt "$WIDTH" ]; then
		WIDTH=${#suite}
	fi
done

REPORT="$LOGS/report.html"
HISTORY=$(history_path)
write_suite_list
write_report running
if [ $open_report -eq 1 ]; then
	open_in_browser
fi

workers=""
keep=""
trap end_run EXIT
trap cancel_run INT TERM
echo "Test user folders: $LOGS/$TEST_DIR_PREFIX<suite>"

# No more workers than suites: the rest would find nothing to claim.
slots=$JOBS
count=$(echo "$suites" | wc -w | tr -d ' ')
if [ "$slots" -gt "$count" ]; then
	slots=$count
fi
while [ "$slots" -gt 0 ]; do
	# shellcheck disable=SC2086
	run_unclaimed $suites &
	workers="$workers $!"
	slots=$((slots - 1))
done

# While the suites run, the report is rewritten every other second.
tick=0
while workers_running; do
	sleep 1
	tick=$((tick + 1))
	if [ $((tick % 2)) -eq 0 ]; then
		judge_finished
		write_report running
	fi
done
wait
judge_finished

# Judged here, not in the workers: verdict() sets $failed, which a background job can't.
for suite in $suites; do
	log=$(suite_log "$suite")
	verdict "$suite" "$(cat "$log.code" 2>/dev/null || echo 1)" "$log"
	if [ "$status" = FAIL ] || [ "$status" = HUNG ]; then
		keep="$keep $(suite_user_root "$suite")"
		echo "    test user folder kept: $(suite_user_root "$suite")"
	fi
done
end_run

if [ $run_launch -eq 1 ]; then
	log="$LOGS/launch.log"
	date +%s >"$log.start"
	write_report running
	$LIMIT "$GODOT" --headless --path "$PROJECT" --quit-after 60 >"$log" 2>&1
	code=$?
	date +%s >"$log.end"
	problems=$(grep -E "$BROKEN|^ERROR:|^WARNING:" "$log")
	if [ -n "$problems" ] || [ $code -ne 0 ]; then
		printf "%-${WIDTH}s %-10s (exit %s)\n" launch FAIL "$code"
		echo "$problems" | head -10 | sed 's/^/    /'
		failed=1
		echo FAIL >"$log.status"
	else
		printf "%-${WIDTH}s %-10s clean (exit 0)\n" launch PASS
		echo PASS >"$log.status"
	fi
fi

write_report done
record_history
echo "Report: $REPORT"
echo "Logs: $LOGS"
if [ $failed -eq 0 ]; then echo "ALL PASS"; else echo "FAILURES ABOVE"; fi
exit $failed
