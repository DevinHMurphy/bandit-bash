#!/bin/sh
# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_captures.sh
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================
# Takes the UI screenshots: runs tools/capture_screens.gd windowed at each size, each size in its
# own throwaway user folder, so a capture never reads or writes the player's own saves. The only
# way captures are run; the tool refuses any other user folder. Works from any folder.
#
#   tools/run_captures.sh                    1280x720, 1920x1080 and 1280x800 (the UI style guide)
#   tools/run_captures.sh 1920x1080 ...      only these sizes
#
# Each run makes one new folder and leaves it for reading:
#   <folder>/shots/<size>/<nn>_<name>.png    the shots
#   <folder>/<size>.log                      the layout report: the tool's SHOT, NOTE, FAIL and
#                                            ISSUE lines and its "--- N shots, M issues ---" line
#   <folder>/user_<size>/                    that size's user folder (its save file 1, Godot's logs)
# The folder is bandit_bash_captures.XXXXXX under $TMPDIR (else /tmp). capture_screens.gd runs
# only with a folder starting bandit_bash_captures on its user folder's path (USER_DIR_PREFIX
# there), so the two names change together.
#
# User folders: as tools/run_tests.sh does, the variable Godot builds user:// from (APPDATA on
# Windows, XDG_DATA_HOME on Linux, HOME on macOS) points at the size's folder, for that one process.
#
# Sizes run one after another, each window at the screen's top left. One verdict line per size:
# PASS (0 issues, no FAIL line, no script error); ISSUES (layout issues, listed); FAIL (a FAIL
# line, a script error, or no summary line); EXIT-CRASH (clean, but the engine crashed at exit,
# Godot issue #117975: the shots stand); HUNG (outlived CAPTURE_TIMEOUT seconds, default 300 as for
# the test suites; 0 turns the limit off). The exit status is 0 only when every size passed.
#
# Godot: $GODOT if set, else `godot` or `godot4` on PATH, else the project's Windows install.
# ==============================================================================

PROJECT="$(cd "$(dirname "$0")/.." && pwd)"
WINDOWS_GODOT="/c/Users/demur/Documents/Godot/Godot_v4.7.1-stable_win64_console.exe"
# capture_screens.gd's USER_DIR_PREFIX: it refuses a user folder without this name on its path.
FOLDER_PREFIX="bandit_bash_captures"
# The UI style guide's sizes: the base, 1080p and the Steam Deck.
DEFAULT_SIZES="1280x720 1920x1080 1280x800"
# Output lines that mean a run is broken, as tools/run_tests.sh reads them.
BROKEN='SCRIPT ERROR|Parse Error|Compile Error|Failed to load script|^ERROR:'
failed=0

sizes="$*"
if [ -z "$sizes" ]; then
	sizes=$DEFAULT_SIZES
fi
for size in $sizes; do
	if ! echo "$size" | grep -qE '^[1-9][0-9]*x[1-9][0-9]*$'; then
		echo "A size is WIDTHxHEIGHT, such as 1920x1080, not '$size'."
		exit 2
	fi
done

if [ -z "$GODOT" ]; then
	GODOT="$(command -v godot || command -v godot4 || echo "$WINDOWS_GODOT")"
fi
if ! "$GODOT" --version >/dev/null 2>&1; then
	echo "Godot not found: set GODOT to the Godot 4.7.1 binary."
	exit 2
fi

# The variable Godot's OS::get_data_path() reads, which user:// sits under. Checked on Windows
# only, as in tools/run_tests.sh.
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

CAPTURE_TIMEOUT="${CAPTURE_TIMEOUT:-300}"
LIMIT=""
if [ "$CAPTURE_TIMEOUT" -gt 0 ]; then
	if command -v timeout >/dev/null 2>&1; then
		LIMIT="timeout -k 10 $CAPTURE_TIMEOUT"
	else
		echo "note: no timeout command, so runs have no time limit"
	fi
fi

# A path as Godot reads it from the environment: a Windows path under Git Bash.
native_path() {
	if [ "$USER_VAR" = APPDATA ] && command -v cygpath >/dev/null 2>&1; then
		cygpath -w "$1"
	else
		echo "$1"
	fi
}

# A path to print, and to pass Godot as an argument: forward slashes, a drive letter on Windows,
# so it opens in Explorer and pastes into Git Bash alike.
shown_path() {
	if command -v cygpath >/dev/null 2>&1; then
		cygpath -m "$1"
	else
		echo "$1"
	fi
}

FOLDER="$(mktemp -d "${TMPDIR:-/tmp}/$FOLDER_PREFIX.XXXXXX")" || exit 2
SHOTS="$FOLDER/shots"
mkdir -p "$SHOTS"
echo "Captures folder: $(shown_path "$FOLDER")"

for size in $sizes; do
	user_root="$FOLDER/user_$size"
	log="$FOLDER/$size.log"
	mkdir -p "$user_root"
	echo "capturing $size ..."
	env "$USER_VAR=$(native_path "$user_root")" $LIMIT "$GODOT" --path "$PROJECT" \
		--script res://tools/capture_screens.gd -- --out "$(shown_path "$SHOTS")" --size "$size" \
		>"$log" 2>&1
	code=$?
	summary=$(grep -E '^--- [0-9]+ shots, [0-9]+ issues ---' "$log" | tail -1)
	issues=$(echo "$summary" | sed -nE 's/.* ([0-9]+) issues.*/\1/p')
	problems=$(grep -cE "^FAIL|$BROKEN" "$log")
	if [ $code -eq 124 ] || [ $code -eq 137 ]; then
		status=HUNG
	elif [ -z "$summary" ] || [ "$problems" -gt 0 ]; then
		status=FAIL
	elif [ "${issues:-1}" -ne 0 ]; then
		status=ISSUES
	elif [ $code -ne 0 ]; then
		status=EXIT-CRASH
	else
		status=PASS
	fi
	printf "%-10s %-10s %s (exit %s)\n" "$size" "$status" "${summary:-no summary line}" "$code"
	case "$status" in
	PASS | EXIT-CRASH) ;;
	*)
		failed=1
		grep -E "^FAIL|^  ISSUE|$BROKEN" "$log" | head -15 | sed 's/^/    /'
		;;
	esac
	echo "    shots:  $(shown_path "$SHOTS/$size")/"
	echo "    report: $(shown_path "$log")"
done

echo "User folders (left for inspection): $(shown_path "$FOLDER")/user_<size>/"
if [ $failed -eq 0 ]; then echo "ALL PASS"; else echo "PROBLEMS ABOVE"; fi
exit $failed
