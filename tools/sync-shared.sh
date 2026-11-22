#!/usr/bin/env sh
# Copies the code the Prof Tool shares with two other repositories into
# project/, at the same paths:
#
# - from the kalulu-frontend submodule, the files listed in shared-files.txt at
#   the repository root, each with its .uid and .import sidecars when the
#   frontend has them: the uid is how scenes find a resource, and the import
#   settings decide how it is imported;
# - from the kalulu-booklets submodule, the booklet generator: the whole of its
#   project/booklets/ folder, into project/booklets/. A file removed there is
#   removed here.
#
# Usage:
#   tools/sync-shared.sh           copy, and say which files changed
#   tools/sync-shared.sh --check   change nothing; exit 1 if project/ has drifted
#                                  from the pinned kalulu-frontend commit
#
# The copies are committed, so a fresh clone opens without running this. Run it
# after moving either submodule pointer, and commit both together.

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

booklets_src="$root/kalulu-booklets/project/booklets"
booklets_dst="$dst/booklets"

if [ ! -f "$src/project.godot" ]; then
	echo "sync-shared: kalulu-frontend/ is not checked out." >&2
	echo "Run: git submodule update --init" >&2
	exit 1
fi
if [ ! -d "$booklets_src" ]; then
	echo "sync-shared: kalulu-booklets/ is not checked out." >&2
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

# The booklet generator, mirrored file for file. Its files depend on nothing
# outside the folder (Kalulu-Booklets' rule), so nothing else is copied.
listing="$(mktemp)"
trap 'rm -f "$listing"' EXIT
(cd "$booklets_src" && find . -type f ! -name .DS_Store | sed 's|^\./||' | sort) > "$listing"
while IFS= read -r file; do
	if [ -f "$booklets_dst/$file" ] && cmp -s "$booklets_src/$file" "$booklets_dst/$file"; then
		continue
	fi
	if [ "$check" -eq 1 ]; then
		if [ -f "$booklets_dst/$file" ]; then
			echo "DIFFERS: booklets/$file" >&2
		else
			echo "MISSING in project: booklets/$file" >&2
		fi
		problems=$((problems + 1))
	else
		mkdir -p "$(dirname -- "$booklets_dst/$file")"
		cp -p "$booklets_src/$file" "$booklets_dst/$file"
		echo "updated booklets/$file"
		changed=$((changed + 1))
	fi
done < "$listing"
if [ -d "$booklets_dst" ]; then
	extra="$(mktemp)"
	(cd "$booklets_dst" && find . -type f ! -name .DS_Store | sed 's|^\./||' | sort) | comm -13 "$listing" - > "$extra"
	while IFS= read -r file; do
		if [ "$check" -eq 1 ]; then
			echo "NOT in kalulu-booklets: booklets/$file" >&2
			problems=$((problems + 1))
		else
			rm -f "$booklets_dst/$file"
			echo "removed booklets/$file"
			changed=$((changed + 1))
		fi
	done < "$extra"
	rm -f "$extra"
fi

frontend_commit="$(git -C "$src" rev-parse --short HEAD)"
booklets_commit="$(git -C "$root/kalulu-booklets" rev-parse --short HEAD)"
pinned="kalulu-frontend $frontend_commit and kalulu-booklets $booklets_commit"
if [ "$check" -eq 1 ]; then
	if [ "$problems" -gt 0 ]; then
		echo "sync-shared: $problems file(s) out of step with $pinned. Run tools/sync-shared.sh." >&2
		exit 1
	fi
	echo "sync-shared: project/ matches $pinned."
else
	[ "$problems" -gt 0 ] && exit 1
	echo "sync-shared: $changed file(s) updated from $pinned."
fi
