#!/bin/sh
# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     setup.sh
# Author:
# Created:  November 25, 2026
# Modified: November 25, 2026
# ==============================================================================
# Sets up the Bandit Bash dev environment around this clone: fetches the two reference repos into
# the folders the project rules expect, and creates the machine-local Steam App ID file.
#
#   Godot_FE/               the old build being rebuilt (read-only reference)
#   steam_multiplayer_kit/  Steam and multiplayer reference (read-only reference)
#   bandit-bash/steam_appid.txt   "480", gitignored, one per machine
#
# Safe to run again: a missing repo is cloned; an existing one is fetched and fast-forwarded only
# when it is clean and on its expected branch, otherwise it is reported and left alone. Nothing
# local is ever overwritten. Run from Git Bash on Windows (or double-click setup.cmd) or from a
# macOS or Linux terminal. Usage: sh setup.sh
# Exit code: 0 everything is in place; 1 a step failed or needs a hand (see the summary).

set -u

ROOT="$(cd "$(dirname "$0")" && pwd)"

# name|url|branch for each reference repo, cloned into $ROOT/<name>.
REPOS="Godot_FE|https://github.com/pellincr/Godot_FE.git|bus/track-b-scaffold
steam_multiplayer_kit|https://github.com/devinhmurphy/steam-multiplayer-kit.git|main"

STEAM_APP_ID_FILE="$ROOT/bandit-bash/steam_appid.txt"
# Valve's public "Spacewar" test App ID, the dev value the kit and the project use.
STEAM_APP_ID="480"

PROBLEMS=0

say() { printf '%s\n' "$*"; }
problem() { say "  ! $*"; PROBLEMS=$((PROBLEMS + 1)); }

if ! command -v git >/dev/null 2>&1; then
	say "git not found. Install Git (Windows: Git for Windows; macOS: xcode-select --install)."
	exit 1
fi

if [ ! -f "$ROOT/bandit-bash/project.godot" ]; then
	say "This script must sit at the root of a bandit-bash clone (no bandit-bash/project.godot"
	say "next to it in $ROOT)."
	exit 1
fi

say "Bandit Bash dev setup in $ROOT"

# Clones a missing repo, or fast-forwards an existing clean one on its expected branch.
sync_repo() {
	name="$1"; url="$2"; branch="$3"; dir="$ROOT/$name"
	say ""
	say "$name ($branch)"

	if [ ! -e "$dir" ]; then
		# core.longpaths: Godot_FE has paths past Windows' 260-character limit, which otherwise
		# fail the checkout. Stored in the clone's config; ignored on macOS and Linux.
		if git clone -c core.longpaths=true --branch "$branch" "$url" "$dir"; then
			say "  cloned"
		else
			problem "clone failed (git's message is above): delete $name/ and rerun"
		fi
		return
	fi

	if [ ! -d "$dir/.git" ]; then
		problem "$dir exists but is not a git clone; move it aside and rerun"
		return
	fi

	git -C "$dir" config core.longpaths true
	if ! git -C "$dir" fetch --quiet origin; then
		problem "fetch failed: check your network and access to $url"
		return
	fi

	current="$(git -C "$dir" rev-parse --abbrev-ref HEAD)"
	if [ "$current" != "$branch" ]; then
		say "  on branch $current, not $branch: left alone (git -C $name checkout $branch)"
		return
	fi
	if [ -n "$(git -C "$dir" status --porcelain --untracked-files=no)" ]; then
		say "  has uncommitted changes: fetched, not updated"
		return
	fi
	if git -C "$dir" merge --ff-only --quiet "origin/$branch"; then
		say "  up to date with origin/$branch"
	else
		problem "can't fast-forward to origin/$branch (local commits?): update it by hand"
	fi
}

OLD_IFS="$IFS"
IFS='
'
for entry in $REPOS; do
	IFS="$OLD_IFS"
	sync_repo "$(echo "$entry" | cut -d'|' -f1)" "$(echo "$entry" | cut -d'|' -f2)" \
		"$(echo "$entry" | cut -d'|' -f3)"
done
IFS="$OLD_IFS"

say ""
say "Steam App ID"
if [ -f "$STEAM_APP_ID_FILE" ]; then
	say "  bandit-bash/steam_appid.txt already present"
elif printf '%s\n' "$STEAM_APP_ID" > "$STEAM_APP_ID_FILE"; then
	say "  created bandit-bash/steam_appid.txt ($STEAM_APP_ID)"
else
	problem "could not write $STEAM_APP_ID_FILE"
fi

say ""
if [ "$PROBLEMS" -eq 0 ]; then
	say "Done. Next: open bandit-bash/project.godot in Godot 4.7.1 (see docs/dev-setup.md)."
	exit 0
fi
say "Finished with $PROBLEMS problem(s), marked ! above. Fix them and rerun; it is safe to repeat."
exit 1
