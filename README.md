# Kalulu Prof Tool

The language-pack editor for [Kalulu](https://github.com/Excello-Recherche-Education/Kalulu-Frontend),
the open-source app that teaches children to read with the grapheme-phoneme method,
developed by [Excello Recherche & Éducation](https://github.com/Excello-Recherche-Education).

A language pack is everything Kalulu needs to teach reading in one language edition:
its grapheme-phoneme pairs, words, syllables, sentences, the lessons that introduce
them, letter tracings, Look & Learn images and videos, and the recordings of every
sound. The Prof Tool is where the team builds and checks them.

It used to live inside the Kalulu-Frontend project. It is now a project of its own;
its history came with it.

## Layout

```
Kalulu-ProfTool/
├── project/              the Godot project — open project/project.godot
├── kalulu-frontend/      submodule: the Kalulu game, pinned to one commit
├── shared-files.txt      what the Prof Tool takes from the game
└── tools/
    ├── setup.sh          one-shot setup for a fresh clone
    └── sync-shared.sh    copy the shared files from kalulu-frontend/
```

The Prof Tool reads and writes the same packs the game plays, so it uses the
game's own code for that: the pack reader (`Database`), its file naming, the
minigame names, plus the Kalulu theme. Those files are listed in
`shared-files.txt` and copied from `kalulu-frontend/` into `project/` **at the same
paths**, so that nothing in either project needs to know about the other.

The copies are committed, so a clone opens straight away. **Never edit them under
`project/`**: change them in Kalulu-Frontend, then bump the submodule here and sync:

```bash
git -C kalulu-frontend fetch && git -C kalulu-frontend checkout <commit>
tools/sync-shared.sh
git add kalulu-frontend project && git commit
```

`tools/sync-shared.sh --check` changes nothing and fails if `project/` has drifted
from the pinned commit.

## Getting started

```bash
git clone --recurse-submodules git@github.com:Excello-Recherche-Education/Kalulu-ProfTool.git
cd Kalulu-ProfTool && tools/setup.sh
```

Then open `project/project.godot` with **Godot 4.7**.

The [godot-sqlite](https://github.com/2shady4u/godot-sqlite) binaries are not in
this repository (nor in Kalulu-Frontend): they are about 320 MB. `tools/setup.sh`
copies them from a Kalulu-Frontend checkout that has them — set `KALULU_FRONTEND`
to its path, or keep it beside this repository. Otherwise install godot-sqlite 4.7
into `project/addons/godot-sqlite/bin` yourself.

## Exporting

Three presets, in `project/export_presets.cfg`: `macOS ProfTool`, `Windows ProfTool`
and `Linux ProfTool`. Always pass an absolute `--path`, create the output folder first,
and check that the artifact exists — Godot's exit code is 0 even when an export fails,
including when the folder is missing:

```bash
mkdir -p build/Linux
godot --headless --path "$PWD/project" --export-release "Linux ProfTool" "$PWD/build/Linux/Prof_Tool-Linux.zip"
```

The macOS build is signed with Excello's **Developer ID** certificate at export
(`codesign/codesign=3`, Xcode `codesign`, the certificate's fingerprint as
`codesign/identity`), then notarized by Apple and the ticket stapled to the app, so
a downloaded copy opens on any Mac without a trip to Privacy & Security. Exporting
the macOS preset therefore needs that certificate and its private key in the
keychain; without them, export the other two presets, or switch `codesign/codesign`
to `1` (ad hoc) for a build you only run yourself.

## License

[Creative Commons Attribution-ShareAlike 4.0 International](LICENSE), like Kalulu.
