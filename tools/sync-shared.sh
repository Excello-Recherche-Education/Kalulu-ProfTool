#!/usr/bin/env sh
# Copies the files the Prof Tool shares with the Kalulu game from the
# kalulu-frontend submodule into project/, at the same paths.
#
# The list is shared-files.txt at the repository root. Each entry is copied with
# its .uid and .import sidecars when the frontend has them: the uid is how scenes
# find a resource, and the import settings decide how it is imported.
#
# Usage:
#   tools/sync-shared.sh           copy, and say which files changed
#   tools/sync-shared.sh --check   change nothing; exit 1 if project/ has drifted
#                                  from the pinned kalulu-frontend commit
#
# The copies are committed, so a fresh clone opens without running this. Run it
# after moving the submodule pointer, and commit both together.

set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
src="$root/kalulu-frontend"
dst="$root/project"
list="$root/shared-files.txt"

case "${1:-}" in
	"")      check=0 ;;
	--check) check=1 ;;
	*)       echo "usage: $0 [--check]" >&2; exit 2 ;;
esac

if [ ! -f "$src/project.godot" ]; then
	echo "sync-shared: kalulu-frontend/ is not checked out." >&2
	echo "Run: git submodule update --init" >&2
	exit 1
fi

problems=0
changed=0

while IFS= read -r entry || [ -n "$entry" ]; do
	case "$entry" in ''|'#'*) continue ;; esac
	if [ ! -f "$src/$entry" ]; then
		echo "MISSING in kalulu-frontend: $entry" >&2
		problems=$((problems + 1))
		continue
	fi
	for file in "$entry" "$entry.uid" "$entry.import"; do
		[ -f "$src/$file" ] || continue
		if [ -f "$dst/$file" ] && cmp -s "$src/$file" "$dst/$file"; then
			continue
		fi
		if [ "$check" -eq 1 ]; then
			if [ -f "$dst/$file" ]; then
				echo "DIFFERS: $file" >&2
			else
				echo "MISSING in project: $file" >&2
			fi
			problems=$((problems + 1))
		else
			mkdir -p "$(dirname -- "$dst/$file")"
			cp -p "$src/$file" "$dst/$file"
			echo "updated $file"
			changed=$((changed + 1))
		fi
	done
done < "$list"

frontend_commit="$(git -C "$src" rev-parse --short HEAD)"
if [ "$check" -eq 1 ]; then
	if [ "$problems" -gt 0 ]; then
		echo "sync-shared: $problems file(s) out of step with kalulu-frontend $frontend_commit. Run tools/sync-shared.sh." >&2
		exit 1
	fi
	echo "sync-shared: project/ matches kalulu-frontend $frontend_commit."
else
	[ "$problems" -gt 0 ] && exit 1
	echo "sync-shared: $changed file(s) updated from kalulu-frontend $frontend_commit."
fi
