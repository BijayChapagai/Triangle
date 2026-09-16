"""diff_place.py must notice when the place and gamedata.json disagree.

Both directions matter: json ahead means the committed place is stale, place
ahead means somebody edited the asset in Studio and the next rebuild from json
would throw that edit away.
"""
import json

import pytest

import rbxlx
from conftest import DIFF, GAMEDATA, PLACE, read, run, write


@pytest.fixture()
def gamedata():
    with open(GAMEDATA, encoding="utf-8") as f:
        return json.load(f)


def test_in_sync():
    code, out = run(DIFF, "--place", PLACE, "--gamedata", GAMEDATA)
    assert code == 0 and "in sync" in out


def test_json_ahead_is_reported(gamedata, tmp_path):
    gamedata["settings"]["BaseFoodTarget"] += 1
    gamedata["codes"].append({"code": "DRIFTED", "cash": 1})
    path = write(tmp_path / "drift.json", json.dumps(gamedata, indent=2))

    code, out = run(DIFF, "--place", PLACE, "--gamedata", path, expect=None)
    assert "settings/BaseFoodTarget" in out
    assert "codes/DRIFTED" in out and "missing from the place" in out
    assert code == 0, "advisory mode must not fail a build"

    code, out = run(DIFF, "--place", PLACE, "--gamedata", path, "--strict", expect=None)
    assert code == 1


def test_place_ahead_is_reported(tmp_path):
    raw = read(PLACE)
    items, order = rbxlx.parse(rbxlx.mask_cdata(raw))
    ref = rbxlx.find(items, order, "ReplicatedStorage/GameData/Codes/RELEASE")
    assert ref
    a, b = items[ref]["start"], items[ref]["end"]
    block = raw[a:b].replace('<string name="Name">RELEASE</string>',
                             '<string name="Name">STUDIO</string>', 1)
    assert block != raw[a:b]
    path = write(tmp_path / "edited.rbxlx", raw[:a] + block + raw[b:])

    code, out = run(DIFF, "--place", path, "--gamedata", GAMEDATA, "--strict", expect=None)
    assert code == 1
    assert "codes/RELEASE" in out, out
    assert "codes/STUDIO" in out and "not in gamedata.json" in out, out


def test_place_ahead_zone_geometry_is_reported(gamedata, tmp_path):
    """Resizing an arena in Studio changes its food pool: that is the drift to
    catch. The geometry lives on the arena's Floor slab."""
    raw = read(PLACE)
    items, order = rbxlx.parse(rbxlx.mask_cdata(raw))
    ref = rbxlx.find(items, order, "Workspace/Zones/Greenfield/Floor")
    assert ref
    a, b = items[ref]["start"], items[ref]["end"]
    block = raw[a:b]
    before = block
    # Both axes: the radius the game reads is half the shorter side, so stretching
    # one axis only would leave the zone exactly as it was.
    block = block.replace("<X>400</X>", "<X>520</X>", 1).replace("<Z>400</Z>", "<Z>520</Z>", 1)
    assert block != before, "the floor size property was not found"
    path = write(tmp_path / "moved.rbxlx", raw[:a] + block + raw[b:])

    code, out = run(DIFF, "--place", path, "--gamedata", GAMEDATA, "--strict", expect=None)
    assert code == 1
    assert "zones/Greenfield/Radius" in out, out


def test_json_dump(tmp_path):
    out_file = str(tmp_path / "place.json")
    run(DIFF, "--place", PLACE, "--gamedata", GAMEDATA, "--json", out_file, "--quiet")
    with open(out_file, encoding="utf-8") as f:
        got = json.load(f)
    assert got["settings"]["GameName"] == "Eat The Cube"
    assert got["zones"]["Greenfield"]["Id"] == 1.0
    assert got["zones"]["Greenfield"]["Top"] == 0.0
    assert got["menuFrames"]["Rebirth"] == {"Frame": True}
    assert got["tabPanels"]["Grow"] == {"Button": True, "Frame": True}
    assert got["tabData"]["Grow"]["Rebirth"]["Target"] == "Rebirth"
    assert got["tabData"]["Deals"]["Favorite"]["Target"] == "@Favorite"
    # read straight back out of the place: a colour written under the wrong
    # property name comes home as None, and loads as black in Studio.
    assert got["tabData"]["Deals"]["Shop"]["Color"] == [249, 173, 0]
    with open(GAMEDATA, encoding="utf-8") as f:
        want = json.load(f)
    assert sorted(got["events"]) == sorted(want["events"])
    assert got["prefs"]["MusicVolume"] == want["prefs"]["MusicVolume"]
