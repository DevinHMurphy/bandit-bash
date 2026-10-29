#!/bin/sh
# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_tests.sh
# Author:
# Created:  October 29, 2026
# Modified: October 29, 2026
# ==============================================================================
# Runs the headless test suites, parse checks and a launch check, and prints one verdict line per
# run, so a result reads in a few lines instead of the full Godot output. Works from any folder.
#
#   tools/run_tests.sh                       every suite, then a headless launch
#   tools/run_tests.sh map combat            only these suites (no launch)
#   tools/run_tests.sh --check <git ref>     parse-check every .gd changed since <git ref>
#   tools/run_tests.sh --check-file res://scripts/a.gd ...
#
# Suites are found, not listed: every tests/<name>/run_all.gd is a suite, and must print a summary
# line "--- N passed, M failed ---" (", K skipped" may follow). A tests/ folder without
# run_all.gd is named in a note and not run.
#
# Verdicts: PASS; FAIL (a failed test, a script or parse error, a leak, or no summary line);
# EXIT-CRASH (every test passed but the engine crashed at exit, Godot issue #117975: the results
# stand). The exit status is 0 only when nothing failed. Each run's full output is kept in the log
# folder printed at the end.
#
# Godot: $GODOT if set, else `godot` or `godot4` on PATH, else the project's Windows install.
# ==============================================================================

PROJECT="$(cd "$(dirname "$0")/.." && pwd)"
WINDOWS_GODOT="/c/Users/demur/OneDrive/Desktop/Godot_v4.7.1-stable_win64.exe"
OVERRIDE="$PROJECT/override.cfg"
LOGS="$(mktemp -d "${TMPDIR:-/tmp}/bandit_tests.XXXXXX")"
failed=0

if [ -z "$GODOT" ]; then
	GODOT="$(command -v godot || command -v godot4 || echo "$WINDOWS_GODOT")"
fi
if ! "$GODOT" --version >/dev/null 2>&1; then
	echo "Godot not found: set GODOT to the Godot 4.7.1 binary."
	exit 2
fi

# Output lines that mean a run is broken, whatever its exit code says.
BROKEN='SCRIPT ERROR|Parse Error|Compile Error|Failed to load script|leaked at exit|resources still in use'

# Prints one verdict line for a finished suite: $1 name, $2 exit code, $3 log file.
verdict() {
	summary=$(grep -E '^--- [0-9]+ passed' "$3" | tail -1)
	broken=$(grep -cE "$BROKEN" "$3")
	fails=$(echo "$summary" | sed -nE 's/.* ([0-9]+) failed.*/\1/p')
	if [ -z "$summary" ] || [ "$broken" -gt 0 ] || [ "${fails:-1}" -ne 0 ]; then
		status=FAIL
	elif [ "$2" -ne 0 ]; then
		status=EXIT-CRASH
	else
		status=PASS
	fi
	printf '%-10s %-10s %s (exit %s)\n' "$1" "$status" "${summary:-no summary line}" "$2"
	if [ "$status" = FAIL ]; then
		failed=1
		grep -E "^FAIL|$BROKEN" "$3" | head -15 | sed 's/^/    /'
	fi
}

# Parse-checks each res:// script given. The output decides: a crash at exit returns 139 even
# when the check itself was fine.
check_scripts() {
	for script in "$@"; do
		log="$LOGS/check_$(basename "$script").log"
		"$GODOT" --headless --path "$PROJECT" --check-only --script "$script" >"$log" 2>&1
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

"$GODOT" --headless --path "$PROJECT" --import >"$LOGS/import.log" 2>&1

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
		else
			echo "note: tests/$name has no run_all.gd, so it is not a suite and was not run"
		fi
	done
	run_launch=1
fi

# The sessions lifecycle tests need a test user folder. Never touch an override.cfg we didn't make.
if [ -e "$OVERRIDE" ]; then
	echo "bandit-bash/override.cfg already exists; remove it (it must never be committed) and rerun."
	exit 2
fi
printf '[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="bandit_bash_tests"\n' >"$OVERRIDE"
trap 'rm -f "$OVERRIDE"' EXIT INT TERM

for suite in $suites; do
	log="$LOGS/$suite.log"
	"$GODOT" --headless --path "$PROJECT" --script "res://tests/$suite/run_all.gd" >"$log" 2>&1
	verdict "$suite" $? "$log"
done
rm -f "$OVERRIDE"

if [ $run_launch -eq 1 ]; then
	log="$LOGS/launch.log"
	"$GODOT" --headless --path "$PROJECT" --quit-after 60 >"$log" 2>&1
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
