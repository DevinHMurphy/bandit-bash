#!/bin/sh
# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_enet_pair.sh
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================
# Opens two windows of the game on this machine, a host and a joiner, playing co-op over the ENet
# dev transport instead of Steam (SteamNetwork's --enet-host= and --enet-join= flags, debug runs
# only), for trying co-op by hand. Each window has its own throwaway user folder, so neither reads
# or writes the player's own saves. Works from any folder.
#
#   tools/run_enet_pair.sh                   a free UDP port on 127.0.0.1
#   tools/run_enet_pair.sh 7777              this port
#
# Both windows open maximized, the project's window mode (Godot's --windowed and --position don't
# change it), one over the other: switch with Alt+Tab or the taskbar, or restore and resize them.
# Then, in each window: make or pick a save file, and choose Multiplayer. The host's window first:
# entering the lobby is what hosts (the status reads "ENet dev transport: hosting on
# 127.0.0.1:<port>"), and then what joins in the other ("joined 127.0.0.1:<port>"). A joiner
# that finds no host gives up after a few seconds; go Back and choose Multiplayer again. Both
# press Ready, and the host starts the campaign. Steam isn't needed, and its lobby buttons stay
# off; players are named "Player <id>". A lost host ends the session (no reconnect over ENet), and
# a run saved here can't be resumed over ENet: the save holds the stand-in ids.
#
# Each launch makes one new folder and leaves it for reading:
#   <folder>/host.log, <folder>/join.log     each window's output (NetLog lines included)
#   <folder>/user_host/, <folder>/user_join/ each window's user folder: its save files, and
#                                            Godot's own log under Godot/app_userdata/<name>/logs/
# The folder is bandit_bash_enet_pair.XXXXXX under $TMPDIR (else /tmp); delete it when done.
#
# User folders: as tools/run_tests.sh does, the variable Godot builds user:// from (APPDATA on
# Windows, XDG_DATA_HOME on Linux, HOME on macOS) points at the window's folder, for that one
# process. The script waits until both windows are closed, then prints how each ended.
#
# Godot: $GODOT if set, else `godot` or `godot4` on PATH, else the project's Windows install.
# ==============================================================================

PROJECT="$(cd "$(dirname "$0")/.." && pwd)"
WINDOWS_GODOT="/c/Users/demur/Documents/Godot/Godot_v4.7.1-stable_win64_console.exe"
FOLDER_PREFIX="bandit_bash_enet_pair"
# SteamNetwork's dev host listens on this machine's loopback only.
ADDRESS="127.0.0.1"
# Where a free port is looked for: the dynamic range, which no service claims. Tries before giving
# up when every port drawn is taken.
FIRST_PORT=49152
LAST_PORT=65535
PORT_TRIES=20

if [ $# -gt 1 ]; then
	echo "Give at most one port, such as 7777."
	exit 2
fi
port="$1"
if [ -n "$port" ]; then
	case "$port" in
	'' | *[!0-9]*)
		echo "A port is a whole number from 1 to 65535, not '$port'."
		exit 2
		;;
	esac
	if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
		echo "A port is a whole number from 1 to 65535, not '$port'."
		exit 2
	fi
fi

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

# A path as Godot reads it from the environment: a Windows path under Git Bash.
native_path() {
	if [ "$USER_VAR" = APPDATA ] && command -v cygpath >/dev/null 2>&1; then
		cygpath -w "$1"
	else
		echo "$1"
	fi
}

# A path to print: forward slashes, a drive letter on Windows, so it opens in Explorer and pastes
# into Git Bash alike.
shown_path() {
	if command -v cygpath >/dev/null 2>&1; then
		cygpath -m "$1"
	else
		echo "$1"
	fi
}

# Whether UDP port $1 is in use here, by netstat's list (Windows' or a Unix one); taken as free
# when there is no netstat to ask.
port_in_use() {
	command -v netstat >/dev/null 2>&1 || return 1
	netstat -an 2>/dev/null | grep -iE 'udp' | grep -qE "[:.]$1[[:space:]]"
}

# A free port drawn from FIRST_PORT to LAST_PORT, or nothing after PORT_TRIES taken ones.
free_port() {
	tries=0
	while [ $tries -lt $PORT_TRIES ]; do
		candidate=$(awk -v low=$FIRST_PORT -v high=$LAST_PORT -v salt="$$$tries" \
			'BEGIN { srand(); srand(srand() + salt); print int(low + rand() * (high - low + 1)) }')
		if ! port_in_use "$candidate"; then
			echo "$candidate"
			return 0
		fi
		tries=$((tries + 1))
	done
}

if [ -z "$port" ]; then
	port=$(free_port)
	if [ -z "$port" ]; then
		echo "No free UDP port found from $FIRST_PORT to $LAST_PORT; give one."
		exit 2
	fi
elif port_in_use "$port"; then
	echo "UDP port $port is in use here; give another, or none for a free one."
	exit 2
fi

FOLDER="$(mktemp -d "${TMPDIR:-/tmp}/$FOLDER_PREFIX.XXXXXX")" || exit 2
mkdir -p "$FOLDER/user_host" "$FOLDER/user_join"

# Starts one window in the background: $1 its role (host or join), $2 its flag. Leaves its
# process id in $launched.
launch() {
	env "$USER_VAR=$(native_path "$FOLDER/user_$1")" "$GODOT" --path "$PROJECT" -- "$2" \
		>"$FOLDER/$1.log" 2>&1 &
	launched=$!
}

launch host "--enet-host=$port"
host_pid=$launched
launch join "--enet-join=$ADDRESS:$port"
join_pid=$launched

echo "ENet pair on $ADDRESS:$port: two windows, the host and the joiner."
echo "  In each: make or pick a save file, then Multiplayer; the host's window first."
echo "  host   user folder: $(shown_path "$FOLDER/user_host")/"
echo "         log:         $(shown_path "$FOLDER/host.log")"
echo "  joiner user folder: $(shown_path "$FOLDER/user_join")/"
echo "         log:         $(shown_path "$FOLDER/join.log")"
echo "Waiting for both windows to close..."

wait $host_pid
host_code=$?
wait $join_pid
join_code=$?
echo "host closed (exit $host_code), joiner closed (exit $join_code)."
echo "Logs and user folders left in $(shown_path "$FOLDER")/; delete it when done."
