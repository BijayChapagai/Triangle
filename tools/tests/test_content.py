"""Invariants on src/gamedata.json - the content contract.

These are the rules that are easy to break by editing a number and hard to notice
in game: a rarity weight that no longer sums to 100, a gift id that no longer
matches its RewardN button, a zone arena dropped on top of the hub arena, or a
DataStore rename that orphans every profile.
"""
import json
import math

import pytest

from conftest import BASE, GAMEDATA, read

# The kinds the server actually handles. Adding one here without a handler in
# Shop.lua / Progression.lua / Gifts.lua is a bug, and vice versa.
PRODUCT_KINDS = {"size", "killall", "revive", "revenge"}      # Shop.lua KINDS
PASS_KINDS = {"speed", "cash", "vip"}                          # Players.lua / Shop.lua
QUEST_TYPES = {"eat", "kill", "rebirth", "size"}               # Progression.lua
SKIN_UNLOCKS = {"start", "cash", "size", "rebirth"}            # Progression.lua
GIFT_TYPES = {"Cash", "Size"}                                  # Gifts.lua


@pytest.fixture(scope="session")
def gd():
    with open(GAMEDATA, encoding="utf-8") as f:
        return json.load(f)


def color_ok(c):
    return (isinstance(c, list) and len(c) == 3
            and all(isinstance(v, int) and 0 <= v <= 255 for v in c))


# --- identity ---------------------------------------------------------------

def test_game_name_is_the_rebrand(gd):
    assert gd["settings"]["GameName"] == "Eat The Cube"


def test_datastore_name_never_changes(gd):
    """Renaming this orphans every saved profile. If it must change, migrate."""
    assert gd["settings"]["DataStoreName"] == "Yeah"


def test_group_id(gd):
    assert gd["settings"]["GroupId"] == 34195654


def test_admins(gd):
    ids = [a["userId"] for a in gd["admins"]]
    assert len(ids) == len(set(ids)), "duplicate admin userId"
    assert all(isinstance(i, int) and i > 0 for i in ids)
    assert 7362557250 in ids, "the owner must keep console access"
    assert all(a.get("role") for a in gd["admins"])


# --- settings ---------------------------------------------------------------

def test_settings_are_scalars(gd):
    for k, v in gd["settings"].items():
        assert isinstance(v, (int, float, str, bool)), "%s is a %s" % (k, type(v).__name__)
        assert k[:1].isupper(), "%s should be CamelCase" % k


def test_settings_are_sane(gd):
    s = gd["settings"]
    assert 0 < s["KillSizeTransfer"] <= 1
    assert s["KillSizeCap"] > 0
    assert s["MaxCubeSize"] > 0
    assert s["RespawnCooldown"] >= 0
    assert s["RebirthBase"] > 0 and s["RebirthExponent"] > 1
    assert s["RebirthMultStep"] > 0
    assert s["SpawnInterval"] > 0 and s["SpawnBatch"] > 0
    assert s["LeaderboardThrottle"] > 0 and s["LeaderboardSize"] > 0
    assert s["ZoneFloorThickness"] > 0, "a zone floor has to be a slab, not a plane"
    assert s["ZoneWallThickness"] > 0 and s["ZoneWallHeight"] > 20, (
        "zone walls must be solid and too tall to hop")
    assert s["SpawnRegionMinX"] < s["SpawnRegionMaxX"]
    assert s["SpawnRegionMinZ"] < s["SpawnRegionMaxZ"]
    assert s["VipRegionMinX"] < s["VipRegionMaxX"]
    assert s["WallInnerX"] > s["SpawnRegionMaxX"], "food can spawn inside a wall"
    assert s["VipZoneId"] not in [z["id"] for z in gd["zones"]], (
        "the VIP wing is not a zone arena; VipZoneId must not collide with one")


# --- progression ------------------------------------------------------------

def test_rarity_weights_sum_to_100(gd):
    total = sum(r["weight"] for r in gd["rarities"])
    assert math.isclose(total, 100.0, abs_tol=1e-6), "weights sum to %s" % total


def test_rarities_escalate(gd):
    names = [r["name"] for r in gd["rarities"]]
    assert len(names) == len(set(names))
    # Ordered common -> rare: weight falls while value and size climb.
    by_weight = sorted(gd["rarities"], key=lambda r: -r["weight"])
    values = [r["value"] for r in by_weight]
    sizes = [r["size"] for r in by_weight]
    assert values == sorted(values), "rarer cubes must be worth more: %s" % values
    assert sizes == sorted(sizes), "rarer cubes must be bigger: %s" % sizes
    assert all(color_ok(r["color"]) for r in gd["rarities"])


def test_ranks_increase(gd):
    names = [r["name"] for r in gd["ranks"]]
    assert len(names) == len(set(names))
    thresholds = [r["threshold"] for r in gd["ranks"]]
    assert thresholds == sorted(thresholds), "ranks must be listed in ascending order"
    assert thresholds[0] == 0


def test_skins(gd):
    ids = [s["id"] for s in gd["skins"]]
    assert len(ids) == len(set(ids))
    assert all(s["unlock"] in SKIN_UNLOCKS for s in gd["skins"])
    assert sum(1 for s in gd["skins"] if s["unlock"] == "start") == 1, (
        "exactly one skin is owned from the start")
    assert all(color_ok(s["color"]) for s in gd["skins"])
    assert all(s.get("req", 0) >= 0 for s in gd["skins"])


def test_quests(gd):
    ids = [q["id"] for q in gd["quests"]]
    assert len(ids) == len(set(ids))
    skins = {s["id"] for s in gd["skins"]}
    for q in gd["quests"]:
        assert q["type"] in QUEST_TYPES, "%s has unknown type %s" % (q["id"], q["type"])
        assert q["goal"] > 0
        assert q.get("rewardCash", 0) >= 0
        assert q.get("rewardSkin", "") in skins | {""}
        assert q["text"]


# --- zones ------------------------------------------------------------------

def test_zone_ids_and_rarities(gd):
    ids = [z["id"] for z in gd["zones"]]
    assert len(ids) == len(set(ids)) and all(i > 0 for i in ids)
    names = [z["name"] for z in gd["zones"]]
    assert len(names) == len(set(names))
    rarities = {r["name"] for r in gd["rarities"]}
    assert all(z["rarity"] in rarities for z in gd["zones"])
    assert all(color_ok(z["color"]) for z in gd["zones"])


def test_zone_arenas_are_arenas(gd):
    """A zone is its own arena: floor and walls, big enough to farm inside.

    The hub arena is 561 x 661 studs, so anything much under 300 across reads as
    the old coloured pad with walls bolted on rather than as a second arena.
    """
    for z in gd["zones"]:
        assert z["radius"] >= 150, "%s is %g studs across - a pad, not an arena" % (
            z["name"], z["radius"] * 2)


def test_zone_arenas_do_not_overlap(gd):
    """Two arenas sharing ground would share food and make the gates ambiguous.

    The hub arena is shipped geometry - walls at WallInnerX/WallInnerZ with the
    VIP wing reaching out to VipRegionMaxX - so it is part of the layout too.
    """
    s = gd["settings"]
    wall = s["ZoneWallThickness"]
    hub_x = max(s["WallInnerX"], s["VipRegionMaxX"]) + wall
    hub_z = s["WallInnerZ"] + wall
    boxes = [("the hub arena", -hub_x, hub_x, -hub_z, hub_z)]
    for z in gd["zones"]:
        r = z["radius"] + wall
        cx, cz = z["center"]
        boxes.append((z["name"], cx - r, cx + r, cz - r, cz + r))

    for i, (a_name, a0, a1, a2, a3) in enumerate(boxes):
        for b_name, b0, b1, b2, b3 in boxes[i + 1:]:
            gap = max(max(a0, b0) - min(a1, b1), max(a2, b2) - min(a3, b3))
            assert gap >= 100, "%s and %s are only %.0f studs apart" % (a_name, b_name, gap)


def test_zone_food_pool_scales_with_the_arena(gd):
    """The old pads were 104 studs across and held 60 cubes. An arena 400+ across
    with the same target is a desert, and one much denser than the hub makes the
    hub pointless - so the pool has to sit in the same range as the hub's."""
    s = gd["settings"]
    hub_area = (s["SpawnRegionMaxX"] - s["SpawnRegionMinX"]) * \
        (s["SpawnRegionMaxZ"] - s["SpawnRegionMinZ"])
    hub_density = s["BaseFoodTarget"] / float(hub_area)
    for z in gd["zones"]:
        density = s["ZoneFoodTarget"] / float((2 * z["radius"]) ** 2)
        assert hub_density / 3 <= density <= hub_density * 2, (
            "%s holds %g cubes per stud^2, the hub holds %g" % (z["name"], density, hub_density))


def test_live_cube_count_stays_cheap(gd):
    """Every cube is a part with a Touched connection: the total is a frame-time
    budget, and the zone arenas multiplied it."""
    s = gd["settings"]
    total = s["BaseFoodTarget"] + s["VipFoodTarget"] + s["ZoneFoodTarget"] * len(gd["zones"])
    assert total <= 1600, "%d live cubes is more than the server should carry" % total


def test_rarer_arenas_are_bigger(gd):
    """Bigger arena, rarer cubes: the tier should read from the map itself."""
    rank = {r["name"]: i for i, r in enumerate(sorted(gd["rarities"], key=lambda r: -r["weight"]))}
    ordered = sorted(gd["zones"], key=lambda z: rank[z["rarity"]])
    radii = [z["radius"] for z in ordered]
    assert radii == sorted(radii), "a rarer zone must not be smaller than an easier one"


def test_zone_requirements_escalate_with_rarity(gd):
    """Early zones are size gated, late zones are rebirth gated; rebirth wins.

    So the rule is: a rarer zone never needs fewer rebirths, and two zones on the
    same rebirth tier must still have a rising size gate.
    """
    rank = {r["name"]: i for i, r in enumerate(sorted(gd["rarities"], key=lambda r: -r["weight"]))}
    ordered = sorted(gd["zones"], key=lambda z: rank[z["rarity"]])

    rebirths = [z.get("reqRebirth", 0) for z in ordered]
    assert rebirths == sorted(rebirths), "rarer zones must not need fewer rebirths"

    for i, a in enumerate(ordered):
        for b in ordered[i + 1:]:
            if a.get("reqRebirth", 0) == b.get("reqRebirth", 0):
                assert a.get("reqSize", 0) <= b.get("reqSize", 0), (
                    "%s is rarer than %s but easier to enter" % (b["name"], a["name"]))


# --- economy ----------------------------------------------------------------

def test_gifts_match_their_buttons(gd):
    """Frames/Rewards/Rewards holds RewardN for gift N: ids must be 1..N."""
    ids = sorted(g["id"] for g in gd["gifts"])
    assert ids == list(range(1, len(ids) + 1)), "gift ids must be contiguous from 1"
    times = [g["requiredTime"] for g in sorted(gd["gifts"], key=lambda g: g["id"])]
    assert times == sorted(times), "the ladder must not get easier"
    assert all(g["type"] in GIFT_TYPES and g["reward"] > 0 for g in gd["gifts"])


def test_codes(gd):
    codes = [c["code"] for c in gd["codes"]]
    assert len(codes) == len(set(codes))
    assert all(c["cash"] > 0 for c in gd["codes"])
    assert all(code == code.upper() and code.replace("_", "").isalnum() for code in codes)


def test_products(gd):
    ids = [p["id"] for p in gd["products"]]
    product_ids = [p["productId"] for p in gd["products"]]
    assert len(ids) == len(set(ids))
    assert len(product_ids) == len(set(product_ids)), "two entries share a ProductId"
    for p in gd["products"]:
        assert p["kind"] in PRODUCT_KINDS, "%s has unknown kind %s" % (p["id"], p["kind"])
        assert isinstance(p["productId"], int) and p["productId"] > 0
        assert p.get("amount", 0) >= 0
        assert p["label"]


def test_gamepasses(gd):
    ids = [p["id"] for p in gd["gamepasses"]]
    pass_ids = [p["gamePassId"] for p in gd["gamepasses"]]
    assert len(ids) == len(set(ids))
    assert len(pass_ids) == len(set(pass_ids))
    assert all(p["kind"] in PASS_KINDS for p in gd["gamepasses"])


# --- ui ---------------------------------------------------------------------

def test_menus_have_a_button_slot(gd):
    """Slots are hand-picked; verify.py checks they do not overlap the base HUD."""
    slots = gd["ui"]["menuSlots"]
    assert len(gd["menus"]) <= len(slots), (
        "more menus than slots: add one to ui.menuSlots")
    assert len(set(tuple(s) for s in slots)) == len(slots), "two menus share a slot"
    w, h = gd["ui"]["buttonSize"]
    for x, y in slots:
        assert 0 <= x and x + w <= 1, "slot %s is off screen" % [x, y]
        assert 0 <= y and y + h <= 1, "slot %s is off screen" % [x, y]
    names = [m["name"] for m in gd["menus"]]
    assert len(names) == len(set(names))
    assert all(color_ok(m["color"]) and m["label"] for m in gd["menus"])


def test_ui_numbers_are_in_range(gd):
    ui = gd["ui"]
    for key in ("menuGridX", "menuGridY", "buttonSize"):
        assert all(0 <= v <= 1 for v in ui[key]), "%s must be in scale units" % key
    assert ui["rowHeight"] > 0


def test_events_are_unique_identifiers(gd):
    events = gd["events"]
    assert len(events) == len(set(events))
    assert all(e[:1].isupper() and e.replace("_", "").isalnum() for e in events)


def test_update_log_is_non_empty_text(gd):
    assert gd["updateLog"]
    assert all(isinstance(t, str) and t.strip() for t in gd["updateLog"])


def test_prefs_defaults(gd):
    """The settings menu is built from these, so the types are the contract."""
    prefs = gd["prefs"]
    assert isinstance(prefs["MusicVolume"], float) and 0 <= prefs["MusicVolume"] <= 1
    assert isinstance(prefs["UiScale"], float) and 0.5 <= prefs["UiScale"] <= 2
    for key in ("CameraPunch", "KillFeed", "ReducedMotion", "AutoFarmFlee"):
        assert isinstance(prefs[key], bool), "%s must be a BoolValue" % key


def test_autofarm_distances_are_sane(gd):
    s = gd["settings"]
    assert s["AutoFarmFleeDistance"] > s["AutoFarmAvoidDistance"] > 0
    assert s["AutoFarmMaxRange"] > s["AutoFarmFleeDistance"], (
        "auto-farm must be able to reach further than it runs")
    assert s["AutoFarmMaxRange"] >= min(z["radius"] for z in gd["zones"]) * 2, (
        "auto-farm must reach across the smallest arena or its cubes go unfarmed")
    assert s["ZoneTeleportCooldown"] >= 0
    assert s["SpawnProtection"] >= 0
    assert s["KillFeedMax"] > 0 and s["KillFeedLifetime"] > 0


# --- generated UI wears the shipped look ------------------------------------
# The menus are generated next to a HUD that was built by hand in Studio, so the
# rule is: use its assets, its fonts and its palette. Every check below compares
# gamedata.json against the base place rather than against a hard-coded list, so
# "same assets as the game" stays true if the game's assets change.

@pytest.fixture(scope="session")
def shipped_assets():
    """Every asset URL the base place already references."""
    import re

    return set(re.findall(
        r"<url>((?:rbxassetid://|rbxasset://|https?://[^<]*roblox\.com/asset/)[^<]*)</url>",
        read(BASE)))


def asset_id(url):
    """The numeric id, so rbxassetid://N and the legacy www.roblox.com/asset/?id=N
    form count as the same art - the shipped HUD uses both for the same icons."""
    import re

    m = re.search(r"(\d{5,})", url or "")
    return m.group(1) if m else None


def shipped_ids(shipped_assets):
    return set(filter(None, (asset_id(u) for u in shipped_assets)))


def test_menu_icons_are_assets_the_game_already_ships(gd, shipped_assets):
    shipped = shipped_ids(shipped_assets)
    for menu in gd["menus"]:
        assert asset_id(menu.get("icon")) in shipped, (
            "%s icon %r is not art the base place already uses - the menu bar would "
            "be the only place in the game with that icon" % (menu["name"], menu.get("icon")))


def test_button_plate_is_the_shipped_one(gd, shipped_assets):
    plate = gd["ui"]["buttonPlate"]
    assert asset_id(plate) in shipped_ids(shipped_assets), plate


def test_ui_fonts_are_the_shipped_families(gd, shipped_assets):
    fonts = gd["ui"]["fonts"]
    assert fonts["main"] in shipped_assets, fonts["main"]
    assert fonts["alt"] in shipped_assets, fonts["alt"]
    assert fonts["mainWeight"] in (400, 500, 700, 900)
    assert fonts["altWeight"] in (400, 500, 700, 900)


def test_menu_buttons_sit_in_the_free_top_band(gd):
    """One row along the top: the original HUD owns both side columns (Invite
    .. VIP) and the bottom band (2xCash, KillAll, 2xSpeed), and verify.py fails
    the build if a generated button lands on any of them."""
    ui = gd["ui"]
    slots = ui["menuSlots"][:len(gd["menus"])]
    w, h = ui["buttonSize"]
    ys = sorted(set(y for _x, y in slots))
    assert len(ys) == 1, "menu buttons must sit on one row, got %s" % ys
    assert ys[0] + h < 0.2, "the menu row belongs above the original HUD (y=%s)" % ys[0]

    xs = [x for x, _y in slots]
    assert xs == sorted(xs), "slots must run left to right"
    for a, b in zip(xs, xs[1:]):
        assert b - a >= w, "buttons at %s and %s would touch (width %s)" % (a, b, w)
    assert xs[0] >= 0 and xs[-1] + w <= 1, "the row must fit on screen"


def test_ui_palette_is_real_colors(gd):
    ui = gd["ui"]
    keys = ("panelColor", "panelStroke", "titleColor", "rowColor", "rowStroke", "rowText",
            "subText", "sectionColor", "sectionText", "actionColor", "closeColor",
            "inputColor", "inputText", "barTrack", "barFill", "accent", "buttonStroke")
    for key in keys:
        assert color_ok(ui[key]), "%s is %r" % (key, ui[key])
    for menu in gd["menus"]:
        assert color_ok(menu["color"]), menu
    for key in ("killFeed", "zoneWarn"):
        for name, value in ui[key].items():
            if isinstance(value, list):
                assert color_ok(value), "%s.%s is %r" % (key, name, value)


def test_notifier_kinds_match_the_palette(gd):
    """Toasts, quest rows and zone rows all mean the same thing by a colour."""
    kinds = gd["notifier"]["kinds"]
    ui = gd["ui"]
    assert kinds["good"] == ui["actionColor"], "good toasts and action buttons disagree"
    assert kinds["bad"] == [255, 60, 60], kinds["bad"]
    assert kinds["info"] == ui["accent"], "info toasts should use the game purple"
