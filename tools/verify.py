#!/usr/bin/env python3
"""Verify the built place against the sources and the content contract.

Checks, in order:

 1. structure   exactly one Script and one LocalScript, where the plan says,
                and no leftover script instances anywhere else
 2. round trip  every script's <Source> in the built place is byte identical to
                the file in src/ it was built from (catches CDATA/escape damage)
 3. syntax      each authored module is parsed as Lua after a Luau -> Lua
                normalisation pass (needs `pip install luaparser`; skipped
                otherwise). Third party code (ProfileService, FormatNumberAlt)
                is excluded: it uses type annotations this pass does not strip.
 4. references  every name the Lua depends on exists in the asset:
                remote events, GameConfig settings keys, product/gamepass kinds,
                menu frame names, HUD ScreenGui names, `require` targets
 5. style       banned legacy/broken patterns (// comments, wait/spawn/delay,
                bare assert, TODO/placeholder markers)

Usage:  python3 tools/verify.py [--place "eat the cube.rbxlx"] [--quiet]
"""
import argparse
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

import rbxlx          # noqa: E402
import build as plan  # noqa: E402
import content        # noqa: E402

THIRD_PARTY = ("ProfileService", "FormatNumberAlt", "DoubleConversion")

# place path -> src relative path, derived from the build plan
def expected_sources(src_root):
    out = {}
    for path, rel in plan.SOURCES.items():
        final = rename_of(path)
        out[final] = rel
    for path, (rel, _dest) in plan.MOVES.items():
        out[move_target(path)] = rel
    for name in plan.NEW_SERVER_SOURCES:
        out["ServerScriptService/Modules/%s" % name] = "ServerScriptService/Modules/%s.lua" % name
    for name in plan.NEW_SHARED_SOURCES:
        out["ReplicatedStorage/Modules/%s" % name] = "ReplicatedStorage/Modules/%s.lua" % name
    for name in plan.NEW_CLIENT_SOURCES:
        out["ReplicatedFirst/Client/ClientModules/%s" % name] = \
            "ReplicatedFirst/Client/ClientModules/%s.lua" % name
    for name in plan.NEW_MENU_SOURCES:
        out["ReplicatedFirst/Client/ClientModules/Menus/%s" % name] = \
            "ReplicatedFirst/Client/ClientModules/Menus/%s.lua" % name
    return out


def rename_of(path):
    """Final place path of a kept instance: its own rename plus every rename of
    its ancestors (ServerScriptService/Data/Manager -> .../Modules/DataManager)."""
    parts = path.split("/")
    out = []
    for i, _ in enumerate(parts):
        prefix = "/".join(parts[:i + 1])
        entry = plan.KEEP.get(prefix)
        out.append((entry[1] if entry and entry[1] else parts[i]))
    return "/".join(out)


def move_target(path):
    _rel, dest = plan.MOVES[path]
    name = plan.KEEP[path][1]
    # the client bootstrap is renamed too (LoadingClient -> Client)
    dest = rename_of(dest)
    return "%s/ClientModules/%s" % (dest, name)


# ---------------------------------------------------------------------------
# Luau -> Lua normalisation, just enough for a syntax pass
# ---------------------------------------------------------------------------

COMPOUND = re.compile(r"([A-Za-z_][\w.]*(?:\[[^\]]*\])?)\s*(\+=|-=|\*=|/=|\.\.=)\s*")
OP = {"+=": "+", "-=": "-", "*=": "*", "/=": "/", "..=": ".."}


def mask_lua(source):
    """Blank out string literal contents AND comments, keeping byte offsets.

    Used by the annotation stripper, which has to tell a type annotation from a
    method call: `local x: number` is one, `player:SetAttribute(...)` is not, and
    `"Resets in %d:00"` is neither.
    """
    out = list(source)
    i, n = 0, len(source)
    while i < n:
        c = source[i]
        if c in "\"'":
            quote = c
            i += 1
            while i < n:
                if source[i] == "\\":
                    out[i] = " "
                    if i + 1 < n and source[i + 1] != "\n":
                        out[i + 1] = " "
                    i += 2
                    continue
                if source[i] == quote:
                    i += 1
                    break
                if source[i] == "\n":
                    break          # unterminated; stop rather than eat the file
                out[i] = " "
                i += 1
            continue
        if source.startswith("[[", i) or re.match(r"\[=+\[", source[i:i + 12]):
            m = re.match(r"\[(=*)\[", source[i:])
            closer = "]" + m.group(1) + "]"
            end = source.find(closer, i)
            end = n if end < 0 else end + len(closer)
            for j in range(i, end):
                if out[j] != "\n":
                    out[j] = " "
            i = end
            continue
        if source.startswith("--", i):
            if source.startswith("--[[", i) or re.match(r"--\[=+\[", source[i:i + 12]):
                m = re.match(r"--\[(=*)\[", source[i:])
                closer = "]" + m.group(1) + "]"
                end = source.find(closer, i)
                end = n if end < 0 else end + len(closer)
            else:
                end = source.find("\n", i)
                end = n if end < 0 else end
            for j in range(i, end):
                if out[j] != "\n":
                    out[j] = " "
            i = end
            continue
        i += 1
    return "".join(out)


def _match_close(text, open_index):
    """Index of the bracket closing the one at open_index, or None."""
    pairs = {"(": ")", "[": "]", "{": "}"}
    close = pairs.get(text[open_index])
    if not close:
        return None
    depth, i, n = 0, open_index, len(text)
    while i < n:
        if text[i] in "([{":
            depth += 1
        elif text[i] in ")]}":
            depth -= 1
            if depth == 0:
                return i if text[i] == close else None
        i += 1
    return None


def _scan_type(text, i):
    """End offset of the type expression starting at i.

    Handles names (`number`, `Enums.Foo`), optionals (`string?`), unions
    (`number | nil`), tables/arrays (`{number}`, `{ id: number }`), functions
    (`(number) -> string`) and generics-free forms, which is all this project
    uses. Stops at `=`, `,`, `;`, a statement newline or a closing bracket.
    """
    n = len(text)
    while i < n and text[i] in " \t\n\r":
        i += 1
    depth = 0
    while i < n:
        c = text[i]
        if c in "{[(":
            depth += 1
            i += 1
            continue
        if c in "}])":
            if depth == 0:
                break
            depth -= 1
            i += 1
            continue
        if depth == 0:
            if c in "=,;":
                break
            if c == "\n":
                probe = text[i + 1:i + 60].lstrip()
                if probe.startswith("|") or probe.startswith("->"):
                    i += 1
                    continue
                break
            if text.startswith("->", i):
                i += 2
                continue
            if c == "|":
                i += 1
                continue
        i += 1
    return i


def _colon_cuts(text, start, end):
    """Spans of every top-level `: <type>` inside text[start:end]."""
    cuts, depth, i = [], 0, start
    while i < end:
        c = text[i]
        if c in "{[(":
            depth += 1
        elif c in ")]}":
            depth -= 1
        elif c == ":" and depth == 0 and not text.startswith("::", i):
            stop = min(_scan_type(text, i + 1), end)
            cuts.append((i, stop))
            i = stop
            continue
        i += 1
    return cuts


def strip_luau_types(source):
    """Remove Luau-only type syntax so a Lua 5.x parser can read the result.

    Handled: `--!strict` headers, `type X = ...` aliases (single or multi-line),
    annotations on `local` declarations, on function parameters and on return
    types. Deliberately NOT handled: `::` casts, generic parameter lists and
    string interpolation - this project does not use them, and guessing at syntax
    the stripper does not understand is how a check starts lying.

    On a source with no annotations this returns the input unchanged; there is a
    test asserting exactly that for every module in src/.
    """
    masked = mask_lua(source)
    cuts = []

    # Headers are matched against the original text: mask_lua has already blanked
    # them out of `masked`. Worst case (a long string whose line starts with --!)
    # only affects the parse-check copy, never the shipped source.
    for m in re.finditer(r"^[ \t]*--[ \t]*![^\n]*\n?", source, re.M):
        cuts.append(m.span())

    for m in re.finditer(r"\b(?:export[ \t]+)?type[ \t]+[A-Za-z_]\w*[ \t]*=", masked):
        cuts.append((m.start(), _scan_type(masked, m.end())))

    for m in re.finditer(r"\bfunction\b[^()\n]*\(", masked):
        close = _match_close(masked, m.end() - 1)
        if close is None:
            continue
        cuts.extend(_colon_cuts(masked, m.end(), close))
        probe = masked[close + 1:close + 61]
        colon = re.match(r"[ \t\n]*:", probe)
        if colon:
            start = close + 1 + colon.end() - 1
            cuts.append((close + 1 + colon.end() - len(colon.group(0)),
                         _scan_type(masked, start)))

    for m in re.finditer(r"\blocal[ \t]+", masked):
        i, depth, n = m.end(), 0, len(masked)
        j = i
        while j < n:
            c = masked[j]
            if c in "{[(":
                depth += 1
            elif c in ")]}":
                depth -= 1
            elif depth == 0 and (c == "=" or c == "\n"):
                break
            j += 1
        if ":" in masked[i:j]:
            cuts.extend(_colon_cuts(masked, i, j))

    if not cuts:
        return source

    cuts.sort()
    merged = []
    for start, end in cuts:
        if merged and start <= merged[-1][1]:
            merged[-1] = (merged[-1][0], max(merged[-1][1], end))
        else:
            merged.append((start, end))

    out, previous = [], 0
    for start, end in merged:
        out.append(source[previous:start])
        previous = end
    out.append(source[previous:])
    return "".join(out)


def normalize(source):
    """Luau -> Lua 5.x, enough for a parse check.

    * type annotations and aliases are removed (strip_luau_types);
    * `x += 1` (including the inline `if a then x += 1 end` form) becomes
      `x = x + 1`;
    * the Luau-only `continue` statement becomes a dummy local.
    String interpolation is not handled: no module this project ships uses it
    (third party code is excluded from the pass).
    """
    source = strip_luau_types(source)
    text = COMPOUND.sub(lambda m: "%s = %s %s " % (m.group(1), m.group(1), OP[m.group(2)]),
                        source)
    return re.sub(r"\bcontinue\b", "local _continue = nil", text)


def decode_source(raw, item):
    """The text of a <ProtectedString name="Source"> element, as written."""
    start, end = rbxlx.source_span(raw, item)
    text = raw[start:end]
    m = re.search(r"<!\[CDATA\[(.*)\]\]>", text, re.S)
    return m.group(1) if m else text


def strip_comments(source):
    """Blank out Lua comments (keeping byte offsets and line numbers) so style
    and reference checks do not match prose."""
    out = list(source)
    i, n = 0, len(source)
    while i < n:
        c = source[i]
        if c in "\"'":
            quote = c
            i += 1
            while i < n:
                if source[i] == "\\":
                    i += 2
                    continue
                if source[i] == quote or source[i] == "\n":
                    i += 1
                    break
                i += 1
            continue
        if c == "[" and source.startswith("[[", i):
            end = source.find("]]", i)
            end = n if end < 0 else end + 2
            for j in range(i, end):
                if out[j] != "\n":
                    out[j] = " "
            i = end
            continue
        if source.startswith("--", i):
            if source.startswith("--[[", i):
                end = source.find("]]", i)
                end = n if end < 0 else end + 2
            else:
                end = source.find("\n", i)
                end = n if end < 0 else end
            for j in range(i, end):
                out[j] = " "
            i = end
            continue
        i += 1
    return "".join(out)


def syntax_errors(path, source):
    try:
        from luaparser import ast as lua_ast
    except ImportError:
        return None  # not installed: skipped
    try:
        lua_ast.parse(normalize(source))
    except Exception as exc:  # luaparser raises a variety of types
        return "%s: %s" % (os.path.basename(path), str(exc).split("\n")[0][:160])
    return None


# ---------------------------------------------------------------------------
# reference extraction
# ---------------------------------------------------------------------------

REMOTE_CALLS = re.compile(
    r'(?:client|Client|Remotes)\.(?:fire|on|onServer|toClient|toAllClients|get)\(\s*'
    r'(?:player,\s*)?"([A-Za-z0-9_]+)"')
SETTING_KEYS = re.compile(r'GameConfig\.get\(\s*"([^"]+)"')
PRODUCT_KINDS = re.compile(r'getProductByKind\(\s*"([^"]+)"')
PASS_KINDS = re.compile(r'passId\(\s*"([^"]+)"')
KIND_FIELD = re.compile(r'kind\s*=\s*"([a-z0-9]+)"')
KIND_TABLE_KEY = re.compile(r'^\t([a-z0-9]+) = function', re.M)
PASS_ATTRIBUTE_KEYS = re.compile(r'^\t([a-z0-9]+) = "(?:2x|VIP)', re.M)
FRAME_NAMES = re.compile(r'(?:FRAME_NAME\s*=\s*"([^"]+)"|MenuUi\.frame\(\s*"([^"]+)"|'
                         r'MenuUi\.Register\(\s*"([^"]+)")')
GUI_NAMES = re.compile(r'client\.gui\(\s*"([^"]+)"')
PARENT_REQUIRE = re.compile(r'require\(\s*script\.Parent:WaitForChild\(\s*"([^"]+)"\s*\)')
MODULES_REQUIRE = re.compile(r'require\(\s*(?:Modules|holder|menus|modules):WaitForChild\(\s*"([^"]+)"\s*\)')
REPLICATED_REQUIRE = re.compile(
    r'require\(\s*ReplicatedStorage[.:]?(?:Modules)?[:.]?(?:WaitForChild\(\s*)?"?([A-Za-z0-9_]+)"?')

# Instances the code binds to by name. If one is renamed or deleted in Studio the
# matching feature degrades (with a warning) instead of breaking the game, but it
# is still worth failing the build here: these are the contract between the Lua
# and the place.
REQUIRED_ASSETS = [
    # server
    ("ServerScriptService/Server", "the only Script"),
    ("ServerScriptService/Modules/ProfileService", "data store session handler"),
    ("ServerStorage/Character", "the cube template Characters.lua clones"),
    ("ServerStorage/Character/HumanoidRootPart", "the cube's PrimaryPart"),
    ("ServerStorage/Character/PlayerDisplay/PlayerName", "name tag"),
    ("ServerStorage/Character/PlayerDisplay/PlayerSize", "size/rank tag"),
    ("Workspace/Spawns", "spawn points"),
    ("Workspace/VIPDoor", "VIP wing door"),
    ("Workspace/VIPDoor/ClickPart/ClickDetector", "server side VIP prompt"),
    ("ReplicatedStorage/GameData", "all game content"),
    ("ReplicatedStorage/Events", "remote events"),
    # client bootstrap and its templates
    ("ReplicatedFirst/Client", "the only LocalScript"),
    ("ReplicatedFirst/Client/Loading", "loading screen template"),
    ("ReplicatedFirst/Client/Loading/LoadingFrame/Title", "game name / status line"),
    ("ReplicatedFirst/Client/Loading/LoadingFrame/LoadingBar/Bar", "progress fill"),
    ("ReplicatedFirst/Client/Loading/LoadingFrame/LoadingBar/Percentage", "progress text"),
    ("ReplicatedFirst/Client/Loading/LoadingFrame/Skip", "skip button"),
    ("ReplicatedFirst/Client/Notifier", "toast template"),
    ("ReplicatedFirst/Client/Notifier/Toasts/Toast", "one toast"),
    ("ReplicatedFirst/Client/ClientModules", "client modules"),
    ("ReplicatedFirst/Client/ClientModules/Menus", "menu modules"),
    ("ReplicatedFirst/Client/ClientModules/Popups/IncrementUI", "popup ScreenGui"),
    ("ReplicatedFirst/Client/ClientModules/Popups/Cash", "+Cash popup template"),
    ("ReplicatedFirst/Client/ClientModules/Popups/Size", "+Size popup template"),
    ("ReplicatedStorage/UiModule/hoverSound", "button hover sound"),
    ("ReplicatedStorage/UiModule/clickSound", "button click sound"),
    # HUD
    ("StarterGui/Buttons", "HUD + menu bar"),
    ("StarterGui/Buttons/SizeCounter/CurrentSize", "size readout"),
    ("StarterGui/Buttons/AutoFarm", "auto farm toggle"),
    ("StarterGui/Buttons/KillAllButton", "kill all product button"),
    ("StarterGui/Buttons/KillAllButton/Toggle", "kill all click sound"),
    ("StarterGui/Buttons/Music", "music mute toggle"),
    ("StarterGui/Buttons/Favorite", "favourite the experience"),
    ("StarterGui/Buttons/InviteFriends", "invite friends"),
    ("StarterGui/Buttons/Rewards", "rewards menu button"),
    ("StarterGui/Buttons/Store", "size pack buttons"),
    ("StarterGui/Buttons/2xCash", "x2 cash pass button"),
    ("StarterGui/Buttons/2xSpeed", "x2 speed pass button"),
    ("StarterGui/Currency/Cash/Label", "cash readout"),
    # death screen
    ("StarterGui/DeathGui/DeathFrame/Content/DeathInfo", "death message"),
    ("StarterGui/DeathGui/DeathFrame/Content/Buttons/Row1/Respawn", "free respawn"),
    ("StarterGui/DeathGui/DeathFrame/Content/Buttons/Row2/Revive", "paid revive"),
    ("StarterGui/DeathGui/DeathFrame/Content/Buttons/Row2/Revenge", "paid revenge"),
    # menus
    ("StarterGui/Frames", "menu frames"),
    ("StarterGui/Frames/Codes/TextBox", "code entry"),
    ("StarterGui/Frames/Admin/CommandBar/Input", "admin command entry"),
    ("StarterGui/Frames/Admin/CommandBar/Send", "admin run button"),
    ("StarterGui/Frames/Rewards/Rewards", "playtime reward buttons"),
    ("StarterGui/Frames/UpdateLog/ScrollingFrame/template/Main/Number", "log entry version"),
    ("StarterGui/Frames/UpdateLog/ScrollingFrame/template/Main/Update", "log entry text"),
    ("StarterGui/Frames/Shop/ScrollingFrame/VIP/Buy", "VIP pass button"),
    ("StarterGui/Frames/Shop/ScrollingFrame/x2 Cash/Buy", "x2 cash pass button"),
    ("StarterGui/Frames/Shop/ScrollingFrame/x2 Speed/Buy", "x2 speed pass button"),
    ("StarterGui/Frames/VIP/Purchase", "VIP frame purchase button"),
    # generated by content.py from gamedata.json
    ("ReplicatedStorage/GameData/Prefs", "client settings defaults"),
    ("StarterGui/KillFeed", "kill feed"),
    ("StarterGui/KillFeed/Entries", "kill feed container"),
    ("StarterGui/KillFeed/Entries/Entry", "kill feed row template"),
    ("StarterGui/ZoneWarn", "locked zone warning"),
    ("StarterGui/ZoneWarn/Tint", "locked zone edge tint"),
    ("StarterGui/ZoneWarn/Tint/Label", "locked zone reason"),
    ("StarterGui/Frames/Quests/ClaimAll", "claim every ready quest"),
    ("StarterGui/Frames/Quests/Status", "daily reset countdown"),
]

BANNED = [
    (re.compile(r"^\s*//[^\n]*", re.M), "// comment (Lua uses --)"),
    (re.compile(r"(?<![\w.:])wait\s*\("), "legacy wait() - use task.wait()"),
    (re.compile(r"(?<![\w.:])spawn\s*\("), "legacy spawn() - use task.spawn()"),
    (re.compile(r"(?<![\w.:])delay\s*\("), "legacy delay() - use task.delay()"),
    (re.compile(r"^\s*assert\(", re.M), "bare assert() kills the whole script"),
    (re.compile(r"\bTODO\b|\bFIXME\b|placeholder", re.I), "unfinished marker"),
    # Opening a store at module scope runs during require(). In Studio on an
    # unpublished place (or with API access off) it throws, and the throw takes
    # the requiring script down - Server.lua dies and every module after it never
    # loads. Open stores lazily, inside a function, behind pcall.
    (re.compile(r"^local\s+\w+\s*=\s*DataStoreService\s*:\s*Get\w*DataStore\s*\(", re.M),
     "DataStore opened at module scope - throws during require() in Studio and "
     "kills every module loaded after it; open it lazily inside pcall"),
]


def child_names(items, ref):
    return set(items[c]["name"] for c in items[ref]["children"])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--place", default=os.path.join(ROOT, "eat the cube.rbxlx"))
    ap.add_argument("--src", default=os.path.join(ROOT, "src"))
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()

    raw = open(args.place, encoding="utf-8", errors="replace").read()
    data = rbxlx.mask_cdata(raw)
    items, order = rbxlx.parse(data)
    paths = {r: rbxlx.path_of(items, r) for r in order}
    by_path = {}
    for r in order:
        by_path.setdefault(paths[r], []).append(r)

    gd = content.load(args.src)
    problems = []
    notes = []

    # ---- 1. structure -----------------------------------------------------
    scripts = [r for r in order if items[r]["class"] == "Script"]
    locals_ = [r for r in order if items[r]["class"] == "LocalScript"]
    modules = [r for r in order if items[r]["class"] == "ModuleScript"]

    if len(scripts) != 1 or paths[scripts[0]] != "ServerScriptService/Server":
        problems.append("expected exactly one Script at ServerScriptService/Server, found %s"
                        % [paths[r] for r in scripts])
    if len(locals_) != 1 or paths[locals_[0]] != "ReplicatedFirst/Client":
        problems.append("expected exactly one LocalScript at ReplicatedFirst/Client, found %s"
                        % [paths[r] for r in locals_])

    # no scripts left in the UI, the map or StarterPlayer
    for r in scripts + locals_ + modules:
        p = paths[r]
        if p.startswith(("StarterGui/", "StarterPlayer/", "Workspace/", "ServerStorage/")):
            problems.append("leftover %s in the asset: %s" % (items[r]["class"], p))

    # ---- 2. round trip ----------------------------------------------------
    expected = expected_sources(args.src)
    for path, rel in sorted(expected.items()):
        if path not in by_path:
            problems.append("missing instance for source %s (expected at %s)" % (rel, path))
            continue
        ref = by_path[path][0]
        got = decode_source(raw, items[ref])
        want = open(os.path.join(args.src, rel), encoding="utf-8").read()
        if got != want:
            problems.append("source at %s does not match %s (round trip damage)" % (path, rel))

    # ---- 3. syntax --------------------------------------------------------
    checked = 0
    try:
        import luaparser  # noqa: F401
    except ImportError:
        notes.append("luaparser not installed - syntax pass skipped (pip install luaparser)")
    for path, rel in sorted(expected.items()):
        if any(part in rel for part in THIRD_PARTY):
            continue
        source = open(os.path.join(args.src, rel), encoding="utf-8").read()
        err = syntax_errors(path, source)
        if err:
            problems.append("syntax: " + err)
        checked += 1

    # ---- 4. references ----------------------------------------------------
    events = child_names(items, by_path["ReplicatedStorage/Events"][0])
    settings = child_names(items, by_path["ReplicatedStorage/GameData/Settings"][0])
    def string_values(folder_path, child_name):
        """The Value of every <child_name> StringValue under each entry of a folder."""
        found = set()
        for entry in items[by_path[folder_path][0]]["children"]:
            for child in items[entry]["children"]:
                if child_name and items[child]["name"] != child_name:
                    continue
                block = data[items[child]["start"]:items[child]["end"]]
                m = re.search(r'<string name="Value">([^<]*)</string>', block)
                if m:
                    found.add(m.group(1))
        return found

    product_kinds = string_values("ReplicatedStorage/GameData/Products", "Kind")
    pass_kinds = string_values("ReplicatedStorage/GameData/Gamepasses", "Kind")
    frames = child_names(items, by_path["StarterGui/Frames"][0])
    guis = child_names(items, by_path["StarterGui"][0])

    def siblings(path):
        parent = path.rsplit("/", 1)[0]
        return child_names(items, by_path[parent][0]) if parent in by_path else set()

    used_events, used_settings, used_products, used_passes = set(), set(), set(), set()
    used_frames, used_guis = set(), set()

    for path, rel in sorted(expected.items()):
        if any(part in rel for part in THIRD_PARTY):
            continue
        source = strip_comments(open(os.path.join(args.src, rel), encoding="utf-8").read())

        used_events |= set(REMOTE_CALLS.findall(source))
        used_settings |= set(SETTING_KEYS.findall(source))
        used_products |= set(PRODUCT_KINDS.findall(source))
        used_passes |= set(PASS_KINDS.findall(source))
        used_guis |= set(GUI_NAMES.findall(source))
        for groups in FRAME_NAMES.findall(source):
            # A bare FRAME_NAME constant reference is not a frame name.
            used_frames |= set(g for g in groups if g and not re.match(r"^[A-Z_][A-Z_0-9]*$", g))

        for name in PARENT_REQUIRE.findall(source):
            if name not in siblings(path):
                problems.append("%s requires script.Parent.%s, which is not there" % (path, name))

        # banned patterns
        for pattern, why in BANNED:
            m = pattern.search(source)
            if m:
                line = source[:m.start()].count("\n") + 1
                problems.append("%s:%d %s" % (rel, line, why))

    for name in sorted(used_events - events):
        problems.append("remote %r is used by the code but missing from ReplicatedStorage.Events" % name)
    for name in sorted(used_settings - settings):
        problems.append("setting %r is read by GameConfig.get but missing from GameData/Settings" % name)
    for name in sorted(used_products - product_kinds):
        problems.append("product kind %r is used but no GameData/Products entry has that Kind" % name)
    for name in sorted(used_passes - pass_kinds):
        problems.append("gamepass kind %r is used but no GameData/Gamepasses entry has that Kind" % name)

    # every product kind in the asset needs a grant handler in the server Shop,
    # and every gamepass kind needs an attribute the client and server agree on
    shop_src = open(os.path.join(args.src, "ServerScriptService/Modules/Shop.lua"),
                    encoding="utf-8").read()
    handled = set(KIND_TABLE_KEY.findall(shop_src))
    for kind in sorted(product_kinds - handled):
        problems.append("GameData/Products has Kind %r but ServerScriptService/Modules/Shop.lua "
                        "has no handler for it - the product would be charged and never granted"
                        % kind)

    players_src = open(os.path.join(args.src, "ServerScriptService/Modules/Players.lua"),
                       encoding="utf-8").read()
    cached_passes = set(PASS_ATTRIBUTE_KEYS.findall(players_src))
    for kind in sorted(pass_kinds - cached_passes):
        problems.append("GameData/Gamepasses has Kind %r but Players.lua does not cache it as an "
                        "attribute - nothing in the game can see that pass" % kind)
    for name in sorted(used_frames - frames):
        problems.append("menu frame %r is used but missing from StarterGui/Frames" % name)
    for name in sorted(used_guis - guis):
        problems.append("ScreenGui %r is used but missing from StarterGui" % name)

    # ---- 4a. shared strings -------------------------------------------------
    # An undefined (or empty) SharedString md5 makes Roblox refuse to open the
    # place at all, so this one is worth checking independently of the build.
    defined = set(m.group(1) for m in rbxlx.SHARED_DEF_RE.finditer(raw))
    missing = sorted(set(rbxlx.SHARED_REF_RE.findall(raw)) - defined)
    if missing:
        problems.append("undefined SharedString md5: %s" % [m or "<empty>" for m in missing[:4]])
    else:
        print("shared     %d definitions, %d reference sites, all resolve"
              % (len(defined), len(rbxlx.SHARED_REF_RE.findall(raw))))

    # ---- 4b. asset contract ------------------------------------------------
    for path, why in REQUIRED_ASSETS:
        if path not in by_path:
            problems.append("missing %s (%s)" % (path, why))

    # generated menus must all follow the List/RowTemplate/SectionTemplate shape
    for menu in gd["menus"]:
        base = "StarterGui/Frames/%s" % menu["name"]
        if base not in by_path:
            continue
        for child in ("List", "Title", "Close"):
            if "%s/%s" % (base, child) not in by_path:
                problems.append("menu frame %s has no %s child" % (base, child))
        for child in ("RowTemplate", "SectionTemplate"):
            if "%s/List/%s" % (base, child) not in by_path:
                problems.append("menu frame %s/List has no %s" % (base, child))
        # the shared row template carries the optional progress bar
        for child in ("RowTemplate/Bar", "RowTemplate/Bar/Fill"):
            if "%s/List/%s" % (base, child) not in by_path:
                problems.append("menu frame %s/List has no %s" % (base, child))

    # HUD buttons must not sit on top of each other: the slots for generated menu
    # buttons are hand-picked because the base HUD already covers most of the
    # screen, and an overlap is invisible until somebody taps the wrong button.
    def rect_of(path):
        ref = by_path[path][0] if path in by_path else None
        if ref is None:
            return None
        block = raw[items[ref]["start"]:items[ref]["end"]]
        block = block[:block.index("</Properties>") + len("</Properties>")]

        def udim2(prop):
            m = re.search(r'<UDim2 name="%s">\s*<XS>([-\d.e]+)</XS>\s*<XO>([-\d.e]+)</XO>'
                          r'\s*<YS>([-\d.e]+)</YS>\s*<YO>([-\d.e]+)</YO>' % prop, block, re.S)
            return [float(g) for g in m.groups()] if m else None

        pos, size = udim2("Position"), udim2("Size")
        if not pos or not size:
            return None
        m = re.search(r'<Vector2 name="AnchorPoint">\s*<X>([-\d.e]+)</X>\s*<Y>([-\d.e]+)</Y>',
                      block, re.S)
        ax, ay = (float(m.group(1)), float(m.group(2))) if m else (0.0, 0.0)
        x0, y0 = pos[0] - ax * size[0], pos[2] - ay * size[2]
        return (x0, y0, x0 + size[0], y0 + size[2])

    buttons = by_path.get("StarterGui/Buttons", [None])[0]
    if buttons:
        rects = []
        for child in items[buttons]["children"]:
            # Only real buttons: the base HUD deliberately layers buttons over the
            # Store panel frame, so counting Frames would report design as damage.
            if items[child]["class"] not in ("TextButton", "ImageButton"):
                continue
            rect = rect_of(rbxlx.path_of(items, child))
            if rect:
                rects.append((items[child]["name"], rect))
        for i, (name_a, a) in enumerate(rects):
            for name_b, b2 in rects[i + 1:]:
                if not (a[2] <= b2[0] or b2[2] <= a[0] or a[3] <= b2[1] or b2[3] <= a[1]):
                    problems.append("HUD buttons overlap: %s and %s" % (name_a, name_b))

    # ---- 5. content sanity ------------------------------------------------
    gift_times = [g["requiredTime"] for g in gd["gifts"]]
    if gift_times != sorted(gift_times):
        problems.append("gift RequiredTime is not monotonically increasing: %s" % gift_times)
    gift_ids = set(str(g["id"]) for g in gd["gifts"])
    rewards = child_names(items, by_path["StarterGui/Frames/Rewards/Rewards"][0])
    missing = set("Reward" + i for i in gift_ids) - rewards
    if missing:
        problems.append("gifts with no button in Frames/Rewards/Rewards: %s" % sorted(missing))

    # place level properties the architecture depends on (see build.PLACE_SETTINGS)
    def prop_of(path, name):
        ref = by_path[path][0] if path in by_path else None
        if ref is None:
            return None
        block = raw[items[ref]["start"]:items[ref]["end"]]
        block = block[:block.index("</Properties>") + len("</Properties>")]
        for entry in rbxlx.scan_props(block):
            if entry["attrs"].get("name") == name:
                return (entry.get("inner", "") or "").strip()
        return None

    for path, _tag, name, want in plan.PLACE_SETTINGS:
        got = prop_of(path, name)
        if got != want:
            problems.append("%s.%s is %r in the place but must be %r "
                            "(custom characters / a single client script depend on it)"
                            % (path, name, got, want))

    admins = child_names(items, by_path["ReplicatedStorage/GameData/Admins"][0])
    if not admins:
        problems.append("GameData/Admins is empty - nobody can use the console")

    # ---- report -----------------------------------------------------------
    print("place      %s (%.2f MB)" % (os.path.basename(args.place), len(raw) / 1048576))
    print("instances  %d | Script %d | LocalScript %d | ModuleScript %d"
          % (len(order), len(scripts), len(locals_), len(modules)))
    print("sources    %d checked for round trip, %d parsed" % (len(expected), checked))
    print("refs       %d events, %d settings, %d product kinds, %d pass kinds, %d frames"
          % (len(used_events), len(used_settings), len(used_products), len(used_passes),
             len(used_frames)))
    for note in notes:
        print("note       " + note)

    if problems:
        print("\n%d PROBLEM(S):" % len(problems))
        for p in problems:
            print("  - " + p)
        return 1
    if not args.quiet:
        print("\nverify: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
