#!/usr/bin/env python3
"""Compare the content in a built place against src/gamedata.json.

gamedata.json is the source of truth for a rebuild; the place is the source of
truth once you start editing in Studio. They can drift, and drift is silent - a
rebuild only adds instances that are not already there, so a Studio edit survives
until somebody regenerates that section from the json.

This reads the place back into the same shape as gamedata.json and reports the
differences section by section:

    python3 tools/diff_place.py                    report, always exit 0
    python3 tools/diff_place.py --strict           exit 1 on any difference (CI)
    python3 tools/diff_place.py --json place.json   also dump what the place says
    python3 tools/diff_place.py --place other.rbxlx

Read the report as direction of drift:
  "missing from the place"  -> gamedata.json is ahead: run tools/build.py
  "not in gamedata.json"    -> the place is ahead: copy the Studio edit back into
                               src/gamedata.json, or it is lost on regeneration
  "json=... place=..."      -> a value changed on one side: pick a winner
"""
import argparse
import json
import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rbxlx  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

SCALAR_RE = {
    "NumberValue": re.compile(r'<(?:float|double) name="Value">([^<]*)</'),
    "IntValue": re.compile(r'<int64 name="Value">([^<]*)</'),
    "StringValue": re.compile(r'<string name="Value">([^<]*)</'),
    "BoolValue": re.compile(r'<bool name="Value">([^<]*)</'),
}
# A Color3Value stores its colour in the property named "Value". Anything else is
# ignored by Roblox, which leaves the value at its black default - and black zone
# colours, black rarity colours and black skins in game. So this only ever
# matches the correct form: a regression shows up as drift instead of shipping.
COLOR_RE = re.compile(r'<Color3 name="Value">\s*<R>([^<]*)</R>\s*<G>([^<]*)</G>\s*<B>([^<]*)</B>')
CFRAME_RE = re.compile(r'<CoordinateFrame name="CFrame">\s*<X>([^<]*)</X>\s*<Y>([^<]*)</Y>\s*<Z>([^<]*)</Z>')
SIZE_RE = re.compile(r'<Vector3 name="size">\s*<X>([^<]*)</X>\s*<Y>([^<]*)</Y>\s*<Z>([^<]*)</Z>')
NAME_RE = re.compile(r'<string name="Name">([^<]*)</string>')


# ---------------------------------------------------------------------------
# reading the place
# ---------------------------------------------------------------------------

class Place(object):
    def __init__(self, path):
        self.raw = open(path, encoding="utf-8", errors="replace").read()
        self.items, self.order = rbxlx.parse(rbxlx.mask_cdata(self.raw))
        # First occurrence wins: the base map has several siblings all named
        # "Part", and aliasing them onto each other would read the wrong one.
        self.by_path = {}
        for ref in self.order:
            self.by_path.setdefault(rbxlx.path_of(self.items, ref), ref)

    def find(self, path):
        return self.by_path.get(path)

    def block(self, ref):
        """The item's <Properties> block only (children excluded)."""
        blk = self.raw[self.items[ref]["start"]:self.items[ref]["end"]]
        cut = blk.index("</Properties>") + len("</Properties>")
        return blk[:cut]

    def children(self, path):
        ref = self.find(path)
        if not ref:
            return []
        return [(self.items[c]["name"], self.items[c]["class"], c)
                for c in self.items[ref]["children"]]

    def names(self, path):
        return [n for n, _cls, _ref in self.children(path)]

    # Anything that can carry content. A zone Part holds value objects directly,
    # so containers are not just Folders.
    VALUE_CLASSES = frozenset(("Folder", "NumberValue", "IntValue", "StringValue",
                               "BoolValue", "Color3Value"))

    def value(self, path):
        return self.value_of(self.find(path))

    def value_of(self, ref):
        """Value object -> python value; container -> {child name: value}.

        Children are resolved through the item tree rather than by path, so
        duplicate sibling names cannot alias onto each other.
        """
        if not ref:
            return None
        cls = self.items[ref]["class"]
        blk = self.block(ref)
        if cls == "Color3Value":
            m = COLOR_RE.search(blk)
            return [int(round(float(m.group(i)) * 255)) for i in (1, 2, 3)] if m else None
        if cls in SCALAR_RE:
            m = SCALAR_RE[cls].search(blk)
            if not m:
                return None
            text = m.group(1)
            if cls == "BoolValue":
                return text == "true"
            if cls == "StringValue":
                return text
            try:
                return float(text)
            except ValueError:
                return text
        return dict((self.items[c]["name"], self.value_of(c))
                    for c in self.items[ref]["children"]
                    if self.items[c]["class"] in self.VALUE_CLASSES)

    def geometry(self, path):
        """(position, size) of a part, or (None, None)."""
        ref = self.find(path)
        if not ref:
            return None, None
        blk = self.block(ref)
        cf = CFRAME_RE.search(blk)
        sz = SIZE_RE.search(blk)
        pos = [float(cf.group(i)) for i in (1, 2, 3)] if cf else None
        size = [float(sz.group(i)) for i in (1, 2, 3)] if sz else None
        return pos, size


def actual(place, gd):
    """Everything content.py generates, read back out of the place.

    Only sections gamedata.json owns are read: the hand-made StarterGui frames
    (Shop, Codes, VIP, Rewards, UpdateLog) are asset, not generated content, so
    comparing them would report drift that is not drift.
    """
    data = "ReplicatedStorage/GameData"
    out = {}

    out["settings"] = place.value(data + "/Settings") or {}
    out["admins"] = place.value(data + "/Admins") or {}
    out["ranks"] = place.value(data + "/Ranks") or {}
    out["rarities"] = place.value(data + "/Rarities") or {}
    out["skins"] = place.value(data + "/Skins") or {}
    out["quests"] = place.value(data + "/Quests") or {}
    out["gifts"] = place.value(data + "/Gifts") or {}
    out["codes"] = place.value(data + "/Codes") or {}
    out["products"] = place.value(data + "/Products") or {}
    out["gamepasses"] = place.value(data + "/Gamepasses") or {}
    out["updateLog"] = place.value(data + "/UpdateLog") or {}
    out["prefs"] = place.value(data + "/Prefs") or {}
    out["events"] = sorted(place.names("ReplicatedStorage/Events"))

    zones = {}
    for name, cls, _ref in place.children("Workspace/Zones"):
        base = "Workspace/Zones/" + name
        entry = place.value(base) or {}
        # A zone is an arena Model and its Floor slab is the geometry the game
        # reads; a hand built zone may still be a bare Part.
        pos, size = place.geometry(base if cls == "Part" else base + "/Floor")
        if pos and size:
            entry["Center"] = [round(pos[0], 3), round(pos[2], 3)]
            entry["Radius"] = round(min(size[0], size[2]) / 2.0, 3)
            entry["Top"] = round(pos[1] + size[1] / 2.0, 3)
        zones[name] = entry
    out["zones"] = zones

    buttons = set(place.names("StarterGui/Buttons"))
    frames = set(name for name, cls, _ref in place.children("StarterGui/Frames") if cls == "Frame")
    tab_items = (gd.get("tabs") or {}).get("items") or []
    # A menu is a panel reached through a tab row, so it needs a frame and
    # nothing else; a tab needs both its HUD button and its launcher panel.
    out["menuFrames"] = dict((m["name"], {"Frame": m["name"] in frames}) for m in gd["menus"])
    out["tabPanels"] = dict((t["name"], {"Button": t["name"] in buttons, "Frame": t["name"] in frames})
                            for t in tab_items)
    out["tabData"] = place.value(data + "/Tabs") or {}

    return out


# ---------------------------------------------------------------------------
# what gamedata.json should produce
# ---------------------------------------------------------------------------

def expected(gd):
    out = {}
    out["settings"] = dict((k, float(v) if isinstance(v, (int, float)) and not isinstance(v, bool) else v)
                           for k, v in gd["settings"].items())
    out["admins"] = dict((a["name"], {"UserId": float(a["userId"]), "Role": a.get("role", "admin")})
                         for a in gd["admins"])
    out["ranks"] = dict((r["name"], float(r["threshold"])) for r in gd["ranks"])
    out["rarities"] = dict((r["name"], {"Weight": float(r["weight"]), "Value": float(r["value"]),
                                        "Size": float(r["size"]), "Color": list(r["color"])})
                           for r in gd["rarities"])
    out["skins"] = dict((s["id"], {"Color": list(s["color"]), "Unlock": s["unlock"],
                                   "Req": float(s.get("req", 0)), "Order": float(i)})
                        for i, s in enumerate(gd["skins"], start=1))
    out["quests"] = dict((q["id"], {"Type": q["type"], "Goal": float(q["goal"]),
                                    "RewardCash": float(q.get("rewardCash", 0)),
                                    "RewardSkin": q.get("rewardSkin", ""),
                                    "Text": q["text"], "Order": float(i)})
                         for i, q in enumerate(gd["quests"], start=1))
    out["gifts"] = dict((str(g["id"]), {"RequiredTime": float(g["requiredTime"]),
                                        "Reward": float(g["reward"]), "Type": g["type"]})
                        for g in gd["gifts"])
    out["codes"] = dict((c["code"], float(c["cash"])) for c in gd["codes"])
    out["products"] = dict((p["id"], {"ProductId": float(p["productId"]), "Kind": p["kind"],
                                      "Amount": float(p.get("amount", 0)),
                                      "Label": p.get("label", p["id"])})
                           for p in gd["products"])
    out["gamepasses"] = dict((p["id"], {"GamePassId": float(p["gamePassId"]), "Kind": p["kind"]})
                             for p in gd["gamepasses"])
    out["updateLog"] = dict((str(i), text) for i, text in enumerate(gd.get("updateLog", []), start=1))
    out["prefs"] = dict((k, float(v) if isinstance(v, (int, float)) and not isinstance(v, bool) else v)
                        for k, v in gd.get("prefs", {}).items())
    out["events"] = sorted(gd["events"])

    floor_y = float(gd["settings"]["FloorY"])
    out["zones"] = dict((z["name"], {"Id": float(z["id"]), "Rarity": z["rarity"],
                                     "ReqSize": float(z.get("reqSize", 0)),
                                     "ReqRebirth": float(z.get("reqRebirth", 0)),
                                     "Color": list(z["color"]),
                                     "Center": [float(z["center"][0]), float(z["center"][1])],
                                     "Radius": float(z["radius"]),
                                     "Top": floor_y})
                        for z in gd["zones"])

    out["menuFrames"] = dict((m["name"], {"Frame": True}) for m in gd["menus"])
    tab_items = (gd.get("tabs") or {}).get("items") or []
    out["tabPanels"] = dict((t["name"], {"Button": True, "Frame": True}) for t in tab_items)
    out["tabData"] = dict(
        (t["name"], dict((e["label"], {"Target": e["target"], "Sub": e.get("sub", ""),
                                       "Order": float(i), "Color": list(e.get("color", t["color"]))})
                         for i, e in enumerate(t["entries"], start=1)))
        for t in tab_items)
    return out


# ---------------------------------------------------------------------------
# diff
# ---------------------------------------------------------------------------

def close(a, b):
    return math.isclose(float(a), float(b), rel_tol=1e-6, abs_tol=1e-6)


def diff(path, want, got, out):
    if isinstance(want, dict) and isinstance(got, dict):
        for key in sorted(set(want) | set(got)):
            if key not in got:
                out.append("%s/%s: in gamedata.json, missing from the place" % (path, key))
            elif key not in want:
                out.append("%s/%s: in the place, not in gamedata.json" % (path, key))
            else:
                diff("%s/%s" % (path, key), want[key], got[key], out)
    elif isinstance(want, list) and isinstance(got, list):
        if len(want) != len(got):
            out.append("%s: list length gamedata.json=%d place=%d" % (path, len(want), len(got)))
        else:
            for i, (a, b) in enumerate(zip(want, got)):
                diff("%s[%d]" % (path, i), a, b, out)
    elif isinstance(want, bool) or isinstance(got, bool):
        if bool(want) != bool(got):
            out.append("%s: gamedata.json=%r place=%r" % (path, want, got))
    elif isinstance(want, (int, float)) and isinstance(got, (int, float)):
        if not close(want, got):
            out.append("%s: gamedata.json=%s place=%s" % (path, want, got))
    elif want != got:
        out.append("%s: gamedata.json=%r place=%r" % (path, want, got))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--place", default=os.path.join(ROOT, "eat the cube.rbxlx"))
    ap.add_argument("--gamedata", default=os.path.join(ROOT, "src", "gamedata.json"))
    ap.add_argument("--strict", action="store_true", help="exit 1 on any difference")
    ap.add_argument("--json", help="write what the place says to this file")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()

    with open(args.gamedata, encoding="utf-8") as f:
        gd = json.load(f)
    place = Place(args.place)
    want, got = expected(gd), actual(place, gd)

    findings = []
    for section in sorted(set(want) | set(got)):
        if section not in got:
            findings.append("%s: whole section missing from the place" % section)
        elif section not in want:
            findings.append("%s: whole section missing from gamedata.json" % section)
        else:
            diff(section, want[section], got[section], findings)

    if args.json:
        with open(args.json, "w", encoding="utf-8") as f:
            json.dump(got, f, indent=2, sort_keys=True)
        if not args.quiet:
            print("wrote %s" % args.json)

    if findings:
        print("%d difference(s) between %s and %s:"
              % (len(findings), os.path.basename(args.gamedata), os.path.basename(args.place)))
        for line in findings:
            print("  - " + line)
        return 1 if args.strict else 0
    if not args.quiet:
        print("content in sync: %s matches %s"
              % (os.path.basename(args.place), os.path.basename(args.gamedata)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
