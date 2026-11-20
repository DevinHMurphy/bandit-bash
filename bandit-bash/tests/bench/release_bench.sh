#!/bin/sh
# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     release_bench.sh
# Author:
# Created:  November 20, 2026
# Modified: November 20, 2026
# ==============================================================================
# Runs a benchmark scene in a release build, the way a player's export runs rules code, and prints
# its output. Works from any folder.
#
#   sh tests/bench/release_bench.sh                          the move preview baseline
#   sh tests/bench/release_bench.sh res://tests/bench/x.tscn  another bench scene
#   sh tests/bench/release_bench.sh res://tests/bench/preview_bench.tscn key_engaged
#                                                            arguments after the scene go to it
#
# A release export template takes no --path, --main-pack or scene argument, so the bench must be
# the exported game's main scene. The script copies the project to a temporary folder, points the
# copy's run/main_scene at the scene, exports it with the "Windows Desktop" preset
# (--export-release, which needs the 4.7.1 release templates installed), runs the export headless
# with the console wrapper, and deletes the folder. Nothing in the checkout changes. Windows only,
# as the only export preset is.
#
# Godot: $GODOT if set, else the project's Windows install.
# ==============================================================================

PROJECT="$(cd "$(dirname "$0")/../.." && pwd)"
SCENE="${1:-res://tests/bench/preview_bench.tscn}"
if [ $# -gt 0 ]; then
	shift
fi
GODOT="${GODOT:-/c/Users/demur/Documents/Godot/Godot_v4.7.1-stable_win64_console.exe}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/bandit_release_bench.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT INT TERM

cp -R "$PROJECT" "$WORK/project"
sed -i "s|^run/main_scene=.*|run/main_scene=\"$SCENE\"|" "$WORK/project/project.godot"
if ! grep -q "^run/main_scene=\"$SCENE\"" "$WORK/project/project.godot"; then
	echo "Could not point the copy's main scene at $SCENE."
	exit 2
fi

EXE="$WORK/bench.exe"
if command -v cygpath >/dev/null 2>&1; then
	EXPORT_PATH="$(cygpath -w "$EXE")"
else
	EXPORT_PATH="$EXE"
fi
"$GODOT" --headless --path "$WORK/project" --export-release "Windows Desktop" "$EXPORT_PATH" \
	>"$WORK/export.log" 2>&1
if [ ! -f "$EXE" ]; then
	echo "The release export failed (are the 4.7.1 export templates installed?):"
	grep -E "ERROR|error" "$WORK/export.log" | head -10
	exit 2
fi
# The preset makes the console wrapper for debug exports only; the game's own exe still prints to
# a pipe, so its output goes through cat.
RUN="$WORK/bench.console.exe"
if [ ! -f "$RUN" ]; then
	RUN="$EXE"
fi
echo "Release export of $SCENE: $(basename "$RUN"), $(du -h "$WORK/bench.pck" | cut -f1) pack"
"$RUN" --headless -- "$@" 2>&1 | cat
