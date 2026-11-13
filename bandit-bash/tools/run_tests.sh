#!/bin/sh
# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_tests.sh
# Author:
# Created:  October 29, 2026
# Modified: November 12, 2026
# ==============================================================================
# Runs the headless test suites, parse checks and a launch check, and prints one verdict line per
# run, so a result reads in a few lines instead of the full Godot output. Works from any folder.
#
#   tools/run_tests.sh                       every suite, then a headless launch
#   tools/run_tests.sh map combat ui/input   only these suites (no launch)
#   tools/run_tests.sh --check <git ref>     parse-check every .gd changed since <git ref>
#   tools/run_tests.sh --check-file res://scripts/a.gd ...
#
# Suites are found, not listed: every tests/<name>/run_all.gd is a suite named <name>, and a
# folder without one may hold suites a level down, tests/<name>/<part>/run_all.gd, named
# <name>/<part> (tests/ui keeps the combat UI's cases shared by its board, input and display
# suites). Each must print a summary line "--- N passed, M failed ---" (", K skipped" may follow).
# A tests/ folder with no suite at either level is named in a note and not run.
#
# Suites run in parallel, at most JOBS Godot processes at once (default: the machine's core count;
# JOBS=1 runs them one after another, in the order found). All suites in a run share its test user
# folder, so any suite whose code mentions user://, SaveFile or SaveService runs one at a time, as
# a group beside the others. A nested suite counts its whole top folder, where shared cases live.
# Verdicts print once every suite has finished, always in the order found.
#
# Test user folder: each run writes a temporary override.cfg pointing user:// at its own folder,
# bandit_bash_tests_<pid>_<random>, in the folder Godot keeps custom user folders in (%APPDATA% on
# Windows), and prints its path. Runs in other worktrees therefore never share it. The run deletes
# that one folder when it ends, passed, failed or interrupted, after copying its logs/ (godot.log
# and any repro dumps) into the log folder as user_logs/.
#
# Verdicts: PASS; FAIL (a failed test, a script or parse error, a leak, or no summary line);
# EXIT-CRASH (every test passed but the engine crashed at exit, Godot issue #117975: the results
# stand); HUNG (the run outlived SUITE_TIMEOUT seconds, default 300, and was stopped: a script
# that fails to compile can leave Godot waiting forever; 0 turns the limit off). The exit status
# is 0 only when nothing failed. Each run's full output is kept in the log folder printed at the
# end. The limit needs `timeout` (coreutils, Git Bash); without it runs are unlimited.
#
# Godot: $GODOT if set, else `godot` or `godot4` on PATH, else the project's Windows install.
# ==============================================================================

PROJECT="$(cd "$(dirname "$0")/.." && pwd)"
WINDOWS_GODOT="/c/Users/demur/Documents/Godot/Godot_v4.7.1-stable_win64_console.exe"
OVERRIDE="$PROJECT/override.cfg"
LOGS="$(mktemp -d "${TMPDIR:-/tmp}/bandit_tests.XXXXXX")"
# The suites refuse a user folder whose name lacks this prefix (tests/ui/ui_suite.gd,
# tests/sessions/sessions_case_base.gd), so it must stay in step with their checks.
TEST_DIR_PREFIX="bandit_bash_tests_"
# Set once the run has a test user folder; end_run deletes only this exact path.
TEST_DIR_NAME=""
TEST_DIR=""
failed=0

if [ -z "$GODOT" ]; then
	GODOT="$(command -v godot || command -v godot4 || echo "$WINDOWS_GODOT")"
fi
if ! "$GODOT" --version >/dev/null 2>&1; then
	echo "Godot not found: set GODOT to the Godot 4.7.1 binary."
	exit 2
fi

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

# Prints one verdict line for a finished suite: $1 name, $2 exit code, $3 log file.
verdict() {
	summary=$(grep -E '^--- [0-9]+ passed' "$3" | tail -1)
	broken=$(grep -cE "$BROKEN" "$3")
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
		grep -E "^FAIL|$BROKEN" "$3" | head -15 | sed 's/^/    /'
	fi
}

# A suite's log file, named with an underscore for a nested suite's slash.
suite_log() {
	echo "$LOGS/$(echo "$1" | tr '/' '_').log"
}

# True when a suite's code can reach the run's test user folder. Comment lines don't count.
uses_user_folder() {
	grep -rh --include='*.gd' -v '^[[:space:]]*#' "$PROJECT/tests/${1%%/*}" 2>/dev/null |
		grep -qE 'user://|SaveFile\.|SaveService'
}

# Runs one suite, leaving its exit code beside its log and its process id for cancel_run.
run_suite() {
	suite_file=$(suite_log "$1")
	$LIMIT "$GODOT" --headless --path "$PROJECT" --script "res://tests/$1/run_all.gd" >"$suite_file" 2>&1 &
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

# Starts a background worker over the suites given.
start_worker() {
	run_unclaimed "$@" &
	workers="$workers $!"
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


# The folder Godot puts a custom user folder in, as OS::get_data_path() resolves it: %APPDATA%
# on Windows, ~/Library/Application Support on macOS, else an absolute $XDG_DATA_HOME or
# ~/.local/share. Prints nothing when it can't tell.
data_folder() {
	case "$(uname -s)" in
	MINGW* | MSYS* | CYGWIN*)
		[ -n "$APPDATA" ] && (cygpath -u "$APPDATA" 2>/dev/null || echo "$APPDATA")
		;;
	Darwin)
		[ -n "$HOME" ] && echo "$HOME/Library/Application Support"
		;;
	*)
		case "$XDG_DATA_HOME" in
		/*) echo "$XDG_DATA_HOME" ;;
		*) [ -n "$HOME" ] && echo "$HOME/.local/share" ;;
		esac
		;;
	esac
}


# Removes the override and this run's test user folder, keeping the folder's logs/. Safe to call
# more than once. Deletes only the exact path built from this run's name, and only when that name
# has the test prefix, so it can't reach another run's folder or the data folder itself. A Godot
# just stopped on Windows can hold files open for a moment, hence the retries.
end_run() {
	rm -f "$OVERRIDE"
	case "$TEST_DIR_NAME" in
	"$TEST_DIR_PREFIX"?*) ;;
	*) return 0 ;;
	esac
	if [ "$(basename "$TEST_DIR")" != "$TEST_DIR_NAME" ] || [ ! -d "$TEST_DIR" ]; then
		return 0
	fi
	if [ -d "$TEST_DIR/logs" ] && [ ! -e "$LOGS/user_logs" ]; then
		cp -R "$TEST_DIR/logs" "$LOGS/user_logs" 2>/dev/null
	fi
	for _attempt in 1 2 3 4 5; do
		rm -rf "$TEST_DIR" 2>/dev/null
		[ -d "$TEST_DIR" ] || return 0
		sleep 1
	done
	echo "warning: could not delete the test user folder $TEST_DIR; delete it by hand."
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

if [ $# -gt 0 ]; then
	suites="$*"
	run_launch=0
else
	suites=""
	for folder in "$PROJECT"/tests/*/; do
		name=$(basename "$folder")
		if [ -f "$folder/run_all.gd" ]; then
			suites="$suites $name"
			continue
		fi
		found=""
		for part in "$folder"*/; do
			if [ -f "$part/run_all.gd" ]; then
				found="$found $name/$(basename "$part")"
			fi
		done
		if [ -n "$found" ]; then
			suites="$suites$found"
		else
			echo "note: tests/$name has no run_all.gd, so it is not a suite and was not run"
		fi
	done
	run_launch=1
fi

# Every suite needs a test user folder, or it would write to the player's real one. Never touch
# an override.cfg or a user folder we didn't make.
if [ -e "$OVERRIDE" ]; then
	echo "bandit-bash/override.cfg already exists; remove it (it must never be committed) and rerun."
	exit 2
fi
data_dir="$(data_folder)"
if [ -z "$data_dir" ] || [ ! -d "$data_dir" ]; then
	echo "Can't find the folder Godot keeps user folders in ('$data_dir'), so the run has none."
	exit 2
fi
random=$(od -An -N4 -tu4 /dev/urandom 2>/dev/null | tr -d ' \n')
dir_name="$TEST_DIR_PREFIX$$_${random:-0}"
if [ -e "$data_dir/$dir_name" ]; then
	echo "Test user folder $data_dir/$dir_name already exists, so it isn't this run's; rerun."
	exit 2
fi
TEST_DIR_NAME="$dir_name"
TEST_DIR="$data_dir/$dir_name"
workers=""
trap end_run EXIT
trap cancel_run INT TERM
printf '[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="%s"\n' \
	"$TEST_DIR_NAME" >"$OVERRIDE"
echo "Test user folder: $TEST_DIR"

user_folder_suites=""
other_suites=""
for suite in $suites; do
	if uses_user_folder "$suite"; then
		user_folder_suites="$user_folder_suites $suite"
	else
		other_suites="$other_suites $suite"
	fi
done

# Word splitting is wanted: suite names have no spaces.
# shellcheck disable=SC2086
if [ "$JOBS" -eq 1 ]; then
	start_worker $suites
else
	# The user folder group is a single worker, and takes one of the JOBS slots.
	slots=$JOBS
	if [ -n "$user_folder_suites" ]; then
		start_worker $user_folder_suites
		slots=$((JOBS - 1))
	fi
	while [ "$slots" -gt 0 ]; do
		start_worker $other_suites
		slots=$((slots - 1))
	done
fi
wait

# Judged here, not in the workers: verdict() sets $failed, which a background job can't.
for suite in $suites; do
	log=$(suite_log "$suite")
	verdict "$suite" "$(cat "$log.code" 2>/dev/null || echo 1)" "$log"
done
# Every Godot run with file logging on writes user://logs, so a missing folder means Godot put it
# somewhere data_folder() doesn't know, and it is left behind there.
if [ ! -d "$TEST_DIR" ]; then
	echo "note: no test user folder at $TEST_DIR; Godot may have made it elsewhere, so it remains"
fi
# The launch below runs without the override, as a player would.
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
