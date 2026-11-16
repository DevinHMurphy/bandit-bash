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
#   tools/run_tests.sh --check <git ref>     parse-check every .gd changed since <git ref>
#   tools/run_tests.sh --check-file res://scripts/a.gd ...
#
# Suites are found, not listed: every tests/<name>/run_all.gd is a suite named <name>, and a
# folder without one may hold suites a level down, tests/<name>/<part>/run_all.gd, named
# <name>/<part> (tests/ui and tests/enemies keep the cases their parts share at the top). Each
# must print a summary line "--- N passed, M failed ---" (", K skipped" may follow).
# A tests/ folder with no suite at either level is named in a note and not run.
#
# Suites run in parallel, at most JOBS Godot processes at once (default: the machine's core count;
# JOBS=1 runs them one after another, in the order found). Verdicts print once every suite has
# finished, always in the order found.
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

PROJECT="$(cd "$(dirname "$0")/.." && pwd)"
WINDOWS_GODOT="/c/Users/demur/Documents/Godot/Godot_v4.7.1-stable_win64_console.exe"
LOGS="$(mktemp -d "${TMPDIR:-/tmp}/bandit_tests.XXXXXX")"
# The suites' guards accept a user folder only with a folder of this name on its path
# (tests/ui/ui_suite.gd, tests/sessions/sessions_case_base.gd), so it must stay in step with them.
TEST_DIR_PREFIX="bandit_bash_tests_"
# What the guarded cases print when they skip for want of a test user folder (the same files).
NO_USER_FOLDER='needs a test user folder'
failed=0
status=""

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

# Prints one verdict line for a finished suite and leaves it in $status: $1 name, $2 exit code,
# $3 log file.
verdict() {
	summary=$(grep -E '^--- [0-9]+ passed' "$3" | tail -1)
	broken=$(grep -cE "$BROKEN|$NO_USER_FOLDER" "$3")
	fails=$(echo "$summary" | sed -nE 's/.* ([0-9]+) failed.*/\1/p')
	if [ "$2" -eq 124 ] || [ "$2" -eq 137 ]; then
		status=HUNG
	elif [ -z "$summary" ] || [ "$broken" -gt 0 ] || [ "${fails:-1}" -ne 0 ]; then
		status=FAIL
	elif [ "$2" -ne 0 ]; then
		status=EXIT-CRASH
	else
		status=PASS
	fi
	printf '%-10s %-10s %s (exit %s)\n' "$1" "$status" "${summary:-no summary line}" "$2"
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

# Runs one suite in its own test user folder, leaving its exit code beside its log and its
# process id for cancel_run.
run_suite() {
	suite_file=$(suite_log "$1")
	user_root=$(suite_user_root "$1")
	mkdir -p "$user_root"
	env "$USER_VAR=$(native_path "$user_root")" $LIMIT "$GODOT" --headless --path "$PROJECT" \
		--script "res://tests/$1/run_all.gd" >"$suite_file" 2>&1 &
	echo $! >"$suite_file.pid"
	wait $!
	echo $? >"$suite_file.code"
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

# On Ctrl+C or kill: stops the workers, so nothing new starts, then the running suites, and ends
# the run only once they are told to stop.
cancel_run() {
	# shellcheck disable=SC2086
	kill $workers 2>/dev/null
	for pid_file in "$LOGS"/*.pid; do
		[ -f "$pid_file" ] && kill "$(cat "$pid_file")" 2>/dev/null
	done
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
			printf '%-10s %-10s %s (exit %s)\n' check FAIL "$script" "$code"
			grep -E "$BROKEN|^ERROR:" "$log" | head -8 | sed 's/^/    /'
			if grep -q 'Identifier not found' "$log"; then
				echo "    (--check-only loads no autoloads: if this names one, cover the script with a suite)"
			fi
			failed=1
		else
			printf '%-10s %-10s %s (exit %s)\n' check PASS "$script" "$code"
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
wait

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
	$LIMIT "$GODOT" --headless --path "$PROJECT" --quit-after 60 >"$log" 2>&1
	code=$?
	problems=$(grep -E "$BROKEN|^ERROR:|^WARNING:" "$log")
	if [ -n "$problems" ] || [ $code -ne 0 ]; then
		printf '%-10s %-10s (exit %s)\n' launch FAIL "$code"
		echo "$problems" | head -10 | sed 's/^/    /'
		failed=1
	else
		printf '%-10s %-10s clean (exit 0)\n' launch PASS
	fi
fi

echo "Logs: $LOGS"
if [ $failed -eq 0 ]; then echo "ALL PASS"; else echo "FAILURES ABOVE"; fi
exit $failed
