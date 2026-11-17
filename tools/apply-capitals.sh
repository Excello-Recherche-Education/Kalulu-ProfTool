#!/usr/bin/env bash
# Sets a language pack's share in capitals to N in M and draws its capitals at
# random, as the Booklets screen's Apply does, without opening the Prof Tool.
# The pack is first upgraded to the Prof Tool's schema version if it is older.
#
#     tools/apply-capitals.sh <pack folder or its language.db> <N> <M>
#     tools/apply-capitals.sh ../Kalulu-Languages/pt_BR 1 3
#
# It edits the pack's language.db in place, and replaces every capital set
# before. Godot is $GODOT, else the one Kalulu-Main's scripts/kalulu-env.sh
# finds when this repository sits in a Kalulu-Main checkout.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(dirname "$here")"

if [ $# -ne 3 ]; then
	echo "usage: $0 <pack folder or language.db> <N> <M>" >&2
	exit 2
fi

if [ -z "${GODOT:-}" ] && [ -f "$repo/../scripts/kalulu-env.sh" ]; then
	# shellcheck disable=SC1091
	. "$repo/../scripts/kalulu-env.sh"
fi
if [ -z "${GODOT:-}" ]; then
	echo "Set GODOT to the Godot 4.7 binary." >&2
	exit 2
fi

pack="$1"
case "$pack" in
	/*) ;;
	*) pack="$PWD/$pack" ;;
esac

# Godot's exit code is not a success signal: the script prints "Done." last
# when it worked, and a line starting with "ERROR:" when it did not.
output="$("$GODOT" --headless --path "$repo/project" --script "$here/apply_capitals.gd" -- "$pack" "$2" "$3" 2>&1)" || true
printf '%s\n' "$output" | grep -v -e '^Godot Engine' -e '^$' || true
printf '%s\n' "$output" | grep -q '^Done\.$'
