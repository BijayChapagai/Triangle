#!/usr/bin/env python3
"""Build "eat the cube.rbxlx" from base_cube.rbxlx + src/.

The place ends up with exactly ONE Script and ONE LocalScript; everything else is
a ModuleScript, and all game content (settings, ranks, rarities, skins, quests,
gifts, codes, products, gamepasses, zones, menus, events) exists as real
instances generated from src/gamedata.json so it can be edited in Studio.

Every change is a byte span over the base file, applied back-to-front:

  source    replace a script's <ProtectedString name="Source">
  rename    replace its <string name="Name">
  class     Script/LocalScript -> ModuleScript or Folder (property surgery)
  delete    drop the whole <Item> block
  move      delete here, re-insert (converted) under the client bootstrap
  inject    brand new instances under an existing parent

Usage:  python3 tools/build.py [--base base_cube.rbxlx] [--out "eat the cube.rbxlx"]
                               [--check]
"""
import re, os, sys, argparse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rbxlx
import content

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASE = os.path.join(ROOT, "base_cube.rbxlx")
OUT = os.path.join(ROOT, "eat the cube.rbxlx")
SRC = os.path.join(ROOT, "src")
SEED = 20240607          # fixed -> byte identical rebuilds

# ---------------------------------------------------------------------------
# the plan
# ---------------------------------------------------------------------------

# Base instances that survive: path -> (final class, final name or None).
# Everything else that is a Script/LocalScript/ModuleScript is deleted; their
# logic lives in the modules injected below.
KEEP = {
    "ReplicatedFirst/LoadingClient": ("LocalScript", "Client"),
    "ReplicatedStorage/UiModule": ("ModuleScript", None),
    "ServerScriptService/Data": ("Folder", "Modules"),
    "ServerScriptService/Data/Manager": ("ModuleScript", "DataManager"),
    "ServerScriptService/Data/ProfileService": ("ModuleScript", None),
    "ServerScriptService/Game": ("Script", "Server"),
    "StarterPlayer/StarterPlayerScripts/UIScaler": ("ModuleScript", "UiScaler"),
    "StarterPlayer/StarterPlayerScripts/VIPDoorHandler": ("ModuleScript", "VipDoor"),
    "StarterPlayer/StarterPlayerScripts/PopupIndicator": ("ModuleScript", "Popups"),
}
# subtrees kept wholesale (third party code, never rewritten)
KEEP_PREFIX = ("ReplicatedStorage/Modules/FormatNumberAlt",)

# base path -> source file in src/, for instances that stay where they are
SOURCES = {
    "ReplicatedFirst/LoadingClient": "ReplicatedFirst/Client.lua",
    "ReplicatedStorage/UiModule": "ReplicatedStorage/UiModule.lua",
    "ServerScriptService/Data/Manager": "ServerScriptService/Modules/DataManager.lua",
    "ServerScriptService/Game": "ServerScriptService/Server.lua",
}

# base path -> (new source, destination parent) for MOVED instances. They carry
# asset children (PopupIndicator owns the +Cash/+Size popup templates), so the
# whole block moves instead of being rebuilt.
CLIENT_BOOTSTRAP = "ReplicatedFirst/LoadingClient"
MOVES = {
    "StarterPlayer/StarterPlayerScripts/UIScaler":
        ("ReplicatedFirst/Client/ClientModules/UiScaler.lua", CLIENT_BOOTSTRAP),
    "StarterPlayer/StarterPlayerScripts/VIPDoorHandler":
        ("ReplicatedFirst/Client/ClientModules/VipDoor.lua", CLIENT_BOOTSTRAP),
    "StarterPlayer/StarterPlayerScripts/PopupIndicator":
        ("ReplicatedFirst/Client/ClientModules/Popups.lua", CLIENT_BOOTSTRAP),
}

NEW_SERVER_PARENT = "ServerScriptService/Data"      # renamed to .../Modules
NEW_SERVER_SOURCES = [
    "Remotes", "Players", "Characters", "Food", "Progression",
    "Leaderboards", "Shop", "Codes", "Gifts", "Admin",
]
NEW_SHARED_SOURCES = ["GameConfig"]                 # -> ReplicatedStorage/Modules
NEW_CLIENT_SOURCES = [                              # -> Client/ClientModules
    "LoadingScreen", "Notifier", "Hud", "DeathScreen", "Camera", "Chat", "CoreGui",
]
NEW_MENU_SOURCES = [                                # -> Client/ClientModules/Menus
    "MenuUi", "Rebirth", "Skins", "Quests", "Zones", "Leaderboard", "Admin",
    "Codes", "Shop", "Rewards", "UpdateLog",
]

# Place level properties this architecture depends on: (path, tag, name, value).
#   CharacterAutoLoads      the cube is assigned by Characters.lua on join, respawn
#                           and revive; Roblox must not spawn a default avatar or
#                           auto-respawn one after a death (the death screen owns
#                           that flow).
#   ResetPlayerGuiOnSpawn   there is exactly one LocalScript now. A PlayerGui
#                           reset would destroy everything it cloned (Notifier,
#                           popups) and leave the bindings pointing at dead
#                           instances - the old per-GUI LocalScripts re-ran on
#                           reset, this one cannot.
#   ResetOnSpawn            same, per ScreenGui.
PLACE_SETTINGS = [
    ("StarterPlayer", "bool", "CharacterAutoLoads", "false"),
    ("StarterGui", "bool", "ResetPlayerGuiOnSpawn", "false"),
    ("StarterGui/Buttons", "bool", "ResetOnSpawn", "false"),
    ("StarterGui/Currency", "bool", "ResetOnSpawn", "false"),
]


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

def read_src(src_root, rel):
    path = os.path.join(src_root, rel)
    if not os.path.exists(path):
        raise SystemExit("missing source file: " + path)
    with open(path, encoding="utf-8") as f:
        return f.read()


def props_region(data, item):
    """Absolute span of the inside of an item's own <Properties> element."""
    open_tag = data.index("<Properties>", item["start"]) + len("<Properties>")
    close_tag = data.index("</Properties>", open_tag)
    return open_tag, close_tag


def convert_block(data, item, new_class, new_name, new_source):
    """A copy of an Item block converted to another script class, with a new name
    and source. Children (asset templates) come along untouched."""
    text = data[item["start"]:item["end"]]
    text = re.sub(r'<Item class="[^"]+"', '<Item class="%s"' % new_class, text, count=1)

    if new_class == "ModuleScript":
        text = re.sub(r'\n\s*<bool name="Disabled">[^<]*</bool>', "", text, count=1)
        text = re.sub(r'\n\s*<token name="RunContext">[^<]*</token>', "", text, count=1)

    if new_name:
        text = re.sub(r'(<string name="Name">)[^<]*(</string>)',
                      lambda m: m.group(1) + rbxlx.esc(new_name) + m.group(2), text, count=1)
    if new_source is not None:
        text = re.sub(rbxlx.SOURCE_RE, lambda m: rbxlx.source_block(new_source), text, count=1)
    return text


def inner_props(builder, cls, name, depth=3):
    """The property block of a freshly generated instance (used to rebuild the
    properties of a converted item, e.g. Script -> Folder)."""
    xml, _ = builder.item(cls, name, {}, depth=depth)
    start = xml.index("<Properties>") + len("<Properties>")
    end = xml.index("</Properties>", start)
    return xml[start:end]


# ---------------------------------------------------------------------------
# build
# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default=BASE)
    ap.add_argument("--out", default=OUT)
    ap.add_argument("--src", default=SRC)
    ap.add_argument("--check", action="store_true", help="validate only, do not write")
    args = ap.parse_args()

    data = open(args.base, encoding="utf-8", errors="replace").read()
    b = rbxlx.Builder(data, seed=SEED)
    items, order = b.items, b.order
    ed = rbxlx.Editor(data)

    paths = {r: rbxlx.path_of(items, r) for r in order}
    by_path = {}
    for r in order:
        by_path.setdefault(paths[r], []).append(r)

    def ref_of(path):
        if path not in by_path:
            raise SystemExit("plan refers to a missing instance: " + path)
        return by_path[path][0]

    def child_names(path):
        ref = ref_of(path)
        return set(items[c]["name"] for c in items[ref]["children"])

    # ---- 1. source overrides for instances that stay put -------------------
    for path, rel in SOURCES.items():
        it = items[ref_of(path)]
        s, e = rbxlx.source_span(data, it)
        ed.replace(s, e, rbxlx.source_block(read_src(args.src, rel)), "source " + path)

    # ---- 2. renames + class conversions (moved items are handled in step 3) -
    converted = 0
    for path, (new_class, new_name) in KEEP.items():
        if path in MOVES:
            continue
        ref = ref_of(path)
        it = items[ref]
        old_class = it["class"]
        final_name = new_name or it["name"]

        if new_class == "Folder" and old_class != "Folder":
            # A Folder has none of the script properties: rebuild the block from
            # the place's own Folder template (this also renames it).
            ps, pe = props_region(data, it)
            ed.replace(ps, pe, inner_props(b, "Folder", final_name), "folder " + path)
            s, e = rbxlx.class_span(data, it)
            ed.replace(s, e, '<Item class="Folder" referent="%s">' % ref, "class " + path)
            converted += 1
            continue

        if final_name != it["name"]:
            s, e = rbxlx.name_span(data, it)
            ed.replace(s, e, '<string name="Name">%s</string>' % rbxlx.esc(final_name),
                       "rename " + path)

        if new_class != old_class:
            s, e = rbxlx.class_span(data, it)
            ed.replace(s, e, '<Item class="%s" referent="%s">' % (new_class, ref),
                       "class " + path)
            converted += 1
            if new_class == "ModuleScript":
                for prop in ("Disabled", "RunContext"):
                    span = rbxlx.prop_span(data, it, prop)
                    if span:
                        start = data.rfind("\n", 0, span[0]) + 1
                        ed.delete(start, span[1], "drop %s on %s" % (prop, path))

    # ---- 3. moves ----------------------------------------------------------
    moved_xml = []
    for path, (rel, _dest) in MOVES.items():
        it = items[ref_of(path)]
        block = convert_block(data, it, "ModuleScript", KEEP[path][1],
                              read_src(args.src, rel))
        moved_xml.append(block)
        ed.delete(it["start"], it["end"], "move " + path)

    # ---- 4. deletions ------------------------------------------------------
    script_classes = ("Script", "LocalScript", "ModuleScript")
    deleted = []
    for ref in order:
        it = items[ref]
        if it["class"] not in script_classes:
            continue
        path = paths[ref]
        if path in KEEP or path in MOVES:
            continue
        if any(path == p or path.startswith(p + "/") for p in KEEP_PREFIX):
            continue
        ed.delete(it["start"], it["end"], "delete " + path)
        deleted.append("%-13s %s" % (it["class"], path))

    # ---- 4b. place level settings ------------------------------------------
    for path, tag, name, value in PLACE_SETTINGS:
        it = items[ref_of(path)]
        element = '<%s name="%s">%s</%s>' % (tag, name, value, tag)
        span = rbxlx.prop_span(data, it, name)
        if span:
            ed.replace(span[0], span[1], element, "setting %s.%s" % (path, name))
        else:
            # Property lists in .rbxlx need not be complete, so a missing
            # property is simply added before the item's own </Properties>.
            _ps, pe = props_region(data, it)
            ed.insert(pe, "\n\t\t\t\t" + element, "setting %s.%s" % (path, name))

    # ---- 5. generated content ---------------------------------------------
    gd = content.load(args.src)

    # never duplicate instances the place already has (keeps rebuilds idempotent
    # even if the base already contains them)
    have_events = child_names("ReplicatedStorage/Events")
    gd["events"] = [e for e in gd["events"] if e not in have_events]
    have_buttons = child_names("StarterGui/Buttons")
    have_frames = child_names("StarterGui/Frames")
    gd_menus = [m for m in gd["menus"]
                if m["name"] not in have_buttons and m["name"] not in have_frames]
    buttons_only = [m for m in gd_menus if m["name"] not in have_buttons]
    frames_only = [m for m in gd_menus if m["name"] not in have_frames]

    chunks = {}
    if not child_names("ReplicatedStorage") & {"GameData"}:
        chunks["ReplicatedStorage"] = content.gamedata(b, gd)
    chunks["ReplicatedStorage/Events"] = content.events(b, gd)
    chunks["StarterGui/Buttons"] = content.menu_buttons(b, dict(gd, menus=buttons_only))
    chunks["StarterGui/Frames"] = content.menu_frames(b, dict(gd, menus=frames_only))
    if "Zones" not in set(items[c]["name"] for c in items[ref_of("Workspace")]["children"]):
        chunks["Workspace"] = content.zones(b, gd)
    chunks[CLIENT_BOOTSTRAP] = content.notifier(b, gd)

    # ---- 6. new modules ----------------------------------------------------
    def modules_xml(names, rel_dir, depth=5):
        out = []
        for name in names:
            rel = os.path.join(rel_dir, name + ".lua")
            out.append(b.script("ModuleScript", name, read_src(args.src, rel), depth=depth)[0])
        return "".join(out)

    chunks[NEW_SERVER_PARENT] = (chunks.get(NEW_SERVER_PARENT, "")
                                 + modules_xml(NEW_SERVER_SOURCES, "ServerScriptService/Modules"))
    chunks["ReplicatedStorage/Modules"] = modules_xml(NEW_SHARED_SOURCES,
                                                     "ReplicatedStorage/Modules")

    client_modules = ("".join(moved_xml)
                      + modules_xml(NEW_CLIENT_SOURCES, "ReplicatedFirst/Client/ClientModules"))
    menus_folder = b.item("Folder", "Menus", {},
                          children=modules_xml(NEW_MENU_SOURCES,
                                               "ReplicatedFirst/Client/ClientModules/Menus"),
                          depth=5)[0]
    chunks[CLIENT_BOOTSTRAP] += b.item("Folder", "ClientModules", {},
                                       children=client_modules + menus_folder,
                                       depth=4)[0]

    # ---- 7. inject ---------------------------------------------------------
    injections = []
    for parent_path, xml in chunks.items():
        if not xml.strip():
            continue
        parent = items[ref_of(parent_path)]
        at = parent["end"] - len("</Item>")
        if data[at:parent["end"]] != "</Item>":
            raise SystemExit("insertion offset for %s is not </Item>" % parent_path)
        injections.append((at, xml, parent_path))
    for at, xml, why in injections:
        ed.insert(at, xml, "inject " + why)

    # ---- 8. apply, clean, validate ----------------------------------------
    out = ed.apply()
    out = rbxlx.fix_mojibake(out)
    out = out.replace("\x00", "").replace("&#0;", "").replace("&#x0;", "")

    problems, stats = rbxlx.validate(out, expect_scripts=1, expect_localscripts=1)

    print("deleted   %d script instances" % len(deleted))
    for line in deleted:
        print("            - " + line)
    print("converted %d (class changes)" % converted)
    print("moved     %d client modules under ReplicatedFirst/Client/ClientModules" % len(MOVES))
    print("injected  %d groups, %d bytes" % (len(injections), sum(len(x) for _, x, _ in injections)))
    print("stats     %s" % stats)

    if problems:
        print("\nPROBLEMS:")
        for p in problems:
            print("  -", p)
        if not args.check:
            raise SystemExit("refusing to write an invalid place")
    else:
        print("validation: OK (exactly 1 Script, 1 LocalScript, XML well formed, "
              "no dangling refs, every script has source)")

    if args.check:
        print("(--check: nothing written)")
        return
    with open(args.out, "w", encoding="utf-8") as f:
        f.write(out)
    print("wrote %s (%.2f MB)" % (args.out, len(out) / 1e6))


if __name__ == "__main__":
    main()
