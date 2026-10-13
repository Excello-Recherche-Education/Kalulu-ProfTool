#!/usr/bin/env sh
# One-shot setup for a fresh clone. Safe to re-run.
#
#   1. checks out the kalulu-frontend submodule;
#   2. installs the godot-sqlite binaries, which no repository carries (they are
#      ~320 MB), by copying them from a Kalulu-Frontend checkout that has them;
#   3. confirms project/ matches the pinned kalulu-frontend commit.
#
# Where the binaries are copied from, in order: $KALULU_FRONTEND, then a
# Kalulu-Frontend folder beside this repository (the Kalulu-Main layout). The
# kalulu-frontend submodule itself never has them: they are gitignored there too.

set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
bin_rel="addons/godot-sqlite/bin"
bin="$root/project/$bin_rel"
libs="libgdsqlite.macos.template_debug.framework
libgdsqlite.macos.template_release.framework
libgdsqlite.windows.template_debug.x86_64.dll
libgdsqlite.windows.template_release.x86_64.dll
libgdsqlite.linux.template_debug.x86_64.so
libgdsqlite.linux.template_release.x86_64.so"

missing_libs() {
	# Prints the desktop libraries absent from the folder given.
	for lib in $libs; do
		[ -e "$1/$lib" ] || echo "$lib"
	done
}

echo "== Submodule"
git -C "$root" submodule update --init
echo "kalulu-frontend at $(git -C "$root/kalulu-frontend" rev-parse --short HEAD)"

echo "== godot-sqlite binaries"
if [ -z "$(missing_libs "$bin")" ]; then
	echo "already installed"
else
	source_bin=""
	for candidate in "${KALULU_FRONTEND:-}" "$root/../Kalulu-Frontend"; do
		[ -n "$candidate" ] || continue
		if [ -d "$candidate/$bin_rel" ] && [ -z "$(missing_libs "$candidate/$bin_rel")" ]; then
			source_bin="$candidate/$bin_rel"
			break
		fi
	done
	if [ -n "$source_bin" ]; then
		mkdir -p "$bin"
		# -P keeps symlinks as symlinks: the macOS frameworks need their
		# Versions/Current layout intact to pass App Store validation.
		cp -RP "$source_bin/." "$bin/"
		echo "copied from $source_bin"
	else
		echo "MISSING — no Kalulu-Frontend checkout with the binaries was found." >&2
		echo "Install godot-sqlite 4.7 from https://github.com/2shady4u/godot-sqlite/releases" >&2
		echo "into project/$bin_rel, or set KALULU_FRONTEND to a checkout that has them." >&2
		echo "Missing:" >&2
		missing_libs "$bin" | sed 's/^/  /' >&2
		exit 1
	fi
fi

echo "== Shared files"
"$root/tools/sync-shared.sh" --check

echo
echo "Ready. Open project/project.godot in Godot 4.7."
