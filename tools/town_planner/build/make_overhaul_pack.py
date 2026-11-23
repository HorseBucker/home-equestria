"""The Ponyville overhaul as one drop-in mod pack (2026-11-17): ponyville_overhaul.pck for the game's mods folder.

usage: python tools/town_planner/build/make_overhaul_pack.py [--base 8919fff] [--version 1.0.0] [--out FILE.pck]
(after the build; the editor must have imported the new textures and sounds once, as the build leaves them)

Every game file the overhaul changed or added since the game's own source (git: --base, the 0.3.1.2 build, up to
the staged files: what `git add` has
staged, so untracked files that are not part of the overhaul never go in; a packed file must not have unstaged
changes), packed at its game path so it replaces the game's (world/modding/mod_loader.gd "replace any game file"),
the way the game ships its own files:
- a script, text scene or text resource (.gd, .tscn, .tres) also gets a <file>.remap pointing at itself: the
  exported game reaches its own through remaps to compiled or binary copies (.gdc, .scn), which would win;
- a text scene or resource goes in without the uid="uid://..." of its [ext_resource] lines (the game does not
  know new UIDs; the path is what loads), as tools/modding/build_mod.gd does;
- an imported asset (a texture, a sound) goes in as its .import file and the imported data it names under
  .godot/imported, not the source file; raw data the game reads itself (pngs of the aerial map, .f32, .json) as is.
Writes res://mods/ponyville_overhaul/mod.json (game_version = the game's version, so it is not held back as an old
mod) and the build marker. Tools, docs and the planner's plans stay out. Pack format 3, Godot 4.5.0, as
tools/mods/pack_mod.py writes.
"""
import argparse, hashlib, json, os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "mods"))
import pack_mod   # noqa: E402  (write_pack)

MOD_ID = "ponyville_overhaul"
OUT_OF_GAME = ("tools/", "docs/", "mods/", ".github/")
UID_RE = re.compile(r'(?m)^(\[ext_resource[^\n]*?) uid="uid://[^"]*"')


EXTRA = ["world/railway/track.scn",
         # (in the game, though under tools/: the terrain's sculpt loader, which picks the town density's ground)
         "tools/editor/terrain_sculptor.gd",
         # (git-ignored with the other background pony textures: Cherry Berry's tail recoloured to her mane, 2026-11-22)
         "world/characters/background/cherry_berry_hair_tail.png"]


def game_version():
    text = open(os.path.join(ROOT, "project.godot"), encoding="utf-8").read()
    return re.search(r'config/version="([^"]+)"', text).group(1)


def changed(base):
    out = subprocess.run(["git", "-C", ROOT, "diff", "--cached", "--name-status", "--no-renames", base], capture_output=True, text=True, check=True).stdout
    unstaged = set(subprocess.run(["git", "-C", ROOT, "diff", "--name-only"], capture_output=True, text=True, check=True).stdout.split())
    files, gone = [], []
    for line in out.splitlines():
        status, path = line.split("\t", 1)
        if path.startswith(OUT_OF_GAME) or path.endswith((".uid", ".md5")):
            continue
        if path in unstaged:
            sys.exit(f"MOD_BUILD_FAILED {path} has changes that are not staged: git add it (or restore it) first")
        (gone if status == "D" else files).append(path)
    return files, gone


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--base", default="8919fff")
    parser.add_argument("--version", default="1.0.0")
    parser.add_argument("--out", default=os.path.join(HERE, "out", MOD_ID + ".pck"))
    args = parser.parse_args()
    paths, gone = changed(args.base)
    # Built files git ignores, which the staged diff cannot see: the railway track with the old line cut out of the
    # town (cut_track.gd; 2026-11-18 play test: without it the old track ran through the houses and floated over
    # the flattened north-east)
    for extra in EXTRA:
        if not os.path.exists(os.path.join(ROOT, extra)):
            sys.exit(f"MOD_BUILD_FAILED {extra} is missing: run the town build first")
        paths.append(extra)
    if gone:
        print("note: deleted from the game, which a pack cannot do (left as the game has them):", gone)
    files = {}
    imported = remapped = 0
    for path in sorted(paths):
        full = os.path.join(ROOT, path)
        if path.endswith(".import"):
            continue                               # with its asset below
        if os.path.exists(full + ".import"):
            text = open(full + ".import", encoding="utf-8").read()
            dests = re.findall(r'"(res://\.godot/imported/[^"]+)"', text.split("[deps]", 1)[-1]) or re.findall(r'path[^=]*="(res://\.godot/imported/[^"]+)"', text)
            if not dests:
                sys.exit(f"MOD_BUILD_FAILED {path}.import names no imported data")
            for dest in dict.fromkeys(dests):
                data_path = os.path.join(ROOT, dest[len("res://"):])
                if not os.path.exists(data_path):
                    sys.exit(f"MOD_BUILD_FAILED {path} is not imported yet: open the project in the editor once")
                files[dest[len("res://"):]] = open(data_path, "rb").read()
            files[path + ".import"] = text.encode("utf-8")
            imported += 1
            continue
        data = open(full, "rb").read()
        if path.endswith((".tscn", ".tres")):
            data = UID_RE.sub(r"\1", data.decode("utf-8")).encode("utf-8")
        if path.endswith((".gd", ".tscn", ".tres")):
            files[path + ".remap"] = ('[remap]\n\npath="res://%s"\n' % path).encode("utf-8")
            remapped += 1
        files[path] = data
    version = game_version()
    manifest = {
        "id": MOD_ID, "name": "Ponyville Overhaul", "version": args.version, "author": "HorseBucker",
        "description": "Ponyville remade based on the official Tails of Equestria map, with new streets, rivers, lakes and "
                       "bridges. Pick from four town density options in Settings > Graphics.",
        "game_version": version,
    }
    files[f"mods/{MOD_ID}/mod.json"] = json.dumps(manifest, indent="\t").encode("utf-8")
    # Data merged into game files the way any mod's are (mod_loader.gd apply_merges: mods/<id>/merge/<game path>),
    # not copies of the files: the schoolhouse's worksheets, globe and telescope (2026-11-23, mitty's Ponyville
    # Schoolhouse built in), from build/overhaul_merge.
    merge_dir = os.path.join(HERE, "overhaul_merge")
    for folder, _, names in os.walk(merge_dir):
        for name in names:
            source = os.path.join(folder, name)
            rel = os.path.relpath(source, merge_dir).replace(os.sep, "/")
            files[f"mods/{MOD_ID}/merge/{rel}"] = open(source, "rb").read()
    files[f"mods/{MOD_ID}/mod.built.json"] = json.dumps({"id": MOD_ID, "version": args.version, "game_version": version,
                                                        "godot": "4.5.0 (make_overhaul_pack.py)", "base": args.base,
                                                        "commit": subprocess.run(["git", "-C", ROOT, "rev-parse", "--short", "HEAD"], capture_output=True, text=True).stdout.strip()},
                                                       indent="\t").encode("utf-8")
    pack_mod.write_pack(files, args.out)
    size = os.path.getsize(args.out)
    print(f"{len(paths)} game files ({imported} imported assets, {remapped} remapped scripts and scenes) -> {len(files)} pack entries, {size / 1048576:.1f} MB")
    print("MOD_BUILT " + os.path.abspath(args.out))


if __name__ == "__main__":
    main()
