#!/usr/bin/env python3
"""Generate the game's CONTENT instances from src/gamedata.json.

Everything the game is made of lives in the place as real, Studio-editable
instances:

  ReplicatedStorage/GameData   settings, admins, ranks, rarities, skins, quests,
                               gifts, codes, products, gamepasses
  ReplicatedStorage/Events     one RemoteEvent per name
  StarterGui/Buttons           the six menu buttons (name == frame name)
  StarterGui/Frames            the six menu frames, each with a RowTemplate the
                               client clones instead of building rows in code
  ReplicatedFirst/Client       the Notifier ScreenGui (toast stack + template)
  Workspace/Zones              one dais Part per zone, carrying its own id,
                               rarity and requirements as value children, plus a
                               sign. Move or resize a dais in Studio and the
                               server follows: it reads the part, not a config.

Runtime Lua never invents game content - it reads these instances.
"""
import json, os

D = 3          # <Item> indentation depth for top level generated instances


# ---------------------------------------------------------------------------
# small value builders
# ---------------------------------------------------------------------------

def num(b, name, value, depth=D + 1):
    return b.item("NumberValue", name, {"Value": float(value)}, depth=depth)[0]


def integer(b, name, value, depth=D + 1):
    return b.bare_item("IntValue", name, [("int64", "Value", int(value))], depth=depth)[0]


def string(b, name, value, depth=D + 1):
    return b.item("StringValue", name, {"Value": str(value)}, depth=depth)[0]


def boolean(b, name, value, depth=D + 1):
    return b.bare_item("BoolValue", name, [("bool", "Value", bool(value))], depth=depth)[0]


def color(b, name, rgb, depth=D + 1):
    return b.bare_item("Color3Value", name, [("Color3", "Color3", tuple(rgb))], depth=depth)[0]


def folder(b, name, children="", depth=D + 1):
    return b.item("Folder", name, {}, children=children, depth=depth)[0]


def value_for(b, name, value, depth=D + 1):
    """Pick the value class from the python type."""
    if isinstance(value, bool):
        return boolean(b, name, value, depth)
    if isinstance(value, int):
        return num(b, name, value, depth)
    if isinstance(value, float):
        return num(b, name, value, depth)
    if isinstance(value, (list, tuple)) and len(value) == 3:
        return color(b, name, value, depth)
    return string(b, name, value, depth)


# ---------------------------------------------------------------------------
# GameData
# ---------------------------------------------------------------------------

def prefs(b, gd):
    """GameData/Prefs: defaults for the client settings menu.

    Values a player changes are saved into their profile; these are what a fresh
    profile starts from, and they stay editable in Studio like every other content.
    """
    return folder(b, "Prefs", "".join(value_for(b, k, v, D + 2)
                                      for k, v in sorted(gd["prefs"].items())), D + 1)


def gamedata(b, gd):
    sections = []

    settings = "".join(value_for(b, k, v, D + 2) for k, v in sorted(gd["settings"].items()))
    sections.append(folder(b, "Settings", settings, D + 1))

    admins = "".join(
        folder(b, a["name"],
               num(b, "UserId", a["userId"], D + 3) + string(b, "Role", a.get("role", "admin"), D + 3),
               D + 2)
        for a in gd["admins"])
    sections.append(folder(b, "Admins", admins, D + 1))

    # rank name -> threshold
    ranks = "".join(num(b, r["name"], r["threshold"], D + 2) for r in gd["ranks"])
    sections.append(folder(b, "Ranks", ranks, D + 1))

    rarities = ""
    for r in gd["rarities"]:
        rarities += folder(b, r["name"],
                           num(b, "Weight", r["weight"], D + 3)
                           + num(b, "Value", r["value"], D + 3)
                           + num(b, "Size", r["size"], D + 3)
                           + color(b, "Color", r["color"], D + 3),
                           D + 2)
    sections.append(folder(b, "Rarities", rarities, D + 1))

    skins = ""
    for order, s in enumerate(gd["skins"], start=1):
        skins += folder(b, s["id"],
                        color(b, "Color", s["color"], D + 3)
                        + string(b, "Unlock", s["unlock"], D + 3)
                        + num(b, "Req", s.get("req", 0), D + 3)
                        + num(b, "Order", order, D + 3),
                        D + 2)
    sections.append(folder(b, "Skins", skins, D + 1))

    quests = ""
    for order, q in enumerate(gd["quests"], start=1):
        quests += folder(b, q["id"],
                         string(b, "Type", q["type"], D + 3)
                         + num(b, "Goal", q["goal"], D + 3)
                         + num(b, "RewardCash", q.get("rewardCash", 0), D + 3)
                         + string(b, "RewardSkin", q.get("rewardSkin", ""), D + 3)
                         + string(b, "Text", q["text"], D + 3)
                         + num(b, "Order", order, D + 3),
                         D + 2)
    sections.append(folder(b, "Quests", quests, D + 1))

    gifts = ""
    for g in gd["gifts"]:
        gifts += folder(b, str(g["id"]),
                        num(b, "RequiredTime", g["requiredTime"], D + 3)
                        + num(b, "Reward", g["reward"], D + 3)
                        + string(b, "Type", g["type"], D + 3),
                        D + 2)
    sections.append(folder(b, "Gifts", gifts, D + 1))

    codes = "".join(num(b, c["code"], c["cash"], D + 2) for c in gd["codes"])
    sections.append(folder(b, "Codes", codes, D + 1))

    products = ""
    for p in gd["products"]:
        products += folder(b, p["id"],
                           num(b, "ProductId", p["productId"], D + 3)
                           + string(b, "Kind", p["kind"], D + 3)
                           + num(b, "Amount", p.get("amount", 0), D + 3)
                           + string(b, "Label", p.get("label", p["id"]), D + 3),
                           D + 2)
    sections.append(folder(b, "Products", products, D + 1))

    passes = ""
    for p in gd["gamepasses"]:
        passes += folder(b, p["id"],
                         num(b, "GamePassId", p["gamePassId"], D + 3)
                         + string(b, "Kind", p["kind"], D + 3),
                         D + 2)
    sections.append(folder(b, "Gamepasses", passes, D + 1))

    # Ordered StringValues named "1", "2", ... so the update log is editable in
    # Studio like everything else.
    log = "".join(string(b, str(i), text, D + 2)
                  for i, text in enumerate(gd.get("updateLog", []), start=1))
    sections.append(folder(b, "UpdateLog", log, D + 1))
    sections.append(prefs(b, gd))

    return folder(b, "GameData", "".join(sections), D)


# ---------------------------------------------------------------------------
# RemoteEvents
# ---------------------------------------------------------------------------

def events(b, gd):
    return "".join(b.item("RemoteEvent", name, {}, depth=D)[0] for name in gd["events"])


# ---------------------------------------------------------------------------
# shared GUI pieces
# ---------------------------------------------------------------------------

def ui_corner(b, radius=8, name="UICorner", depth=D + 2):
    return b.item("UICorner", name, {
        "TopLeftRadius": ("UDim", (0, radius)),
        "TopRightRadius": ("UDim", (0, radius)),
        "BottomLeftRadius": ("UDim", (0, radius)),
        "BottomRightRadius": ("UDim", (0, radius)),
    }, depth=depth)[0]


def ui_stroke(b, rgb, thickness=2, transparency=0.0, depth=D + 2):
    return b.item("UIStroke", "UIStroke", {
        "Color": ("Color3", tuple(rgb)),
        "Thickness": float(thickness),
        "Transparency": float(transparency),
        "ApplyStrokeMode": 0,   # Enum.ApplyStrokeMode.Border
        "Enabled": True,
    }, depth=depth)[0]


def ui_padding(b, left=12, right=12, top=0, bottom=0, depth=D + 2):
    return b.item("UIPadding", "UIPadding", {
        "PaddingLeft": ("UDim", (0, left)),
        "PaddingRight": ("UDim", (0, right)),
        "PaddingTop": ("UDim", (0, top)),
        "PaddingBottom": ("UDim", (0, bottom)),
    }, depth=depth)[0]


def ui_list_layout(b, padding=6, sort_order=2, h_align=0, v_align=0, depth=D + 2):
    """sort_order 2 = LayoutOrder, h_align/v_align 0 = Left/Top."""
    return b.item("UIListLayout", "UIListLayout", {
        "Padding": ("UDim", (0, padding)),
        "SortOrder": sort_order,
        "HorizontalAlignment": h_align,
        "VerticalAlignment": v_align,
        "FillDirection": 1,
        "Wraps": False,
    }, depth=depth)[0]


def text_size(b, max_size, min_size=8, depth=D + 2):
    return b.item("UITextSizeConstraint", "UITextSizeConstraint", {
        "MaxTextSize": int(max_size), "MinTextSize": int(min_size),
    }, depth=depth)[0]


FONT = ('<Font name="FontFace"><Family><url>rbxassetid://12187365977</url></Family>'
        '<Weight>700</Weight><Style>Normal</Style></Font>')


def text_overrides(text, size=17, scaled=False, x_align=0, wrapped=False, rich=True,
                   color=(235, 240, 255), truncate=1):
    return {
        "Text": text,
        "TextSize": float(size),
        "TextScaled": scaled,
        "RichText": rich,
        "TextColor3": ("Color3", tuple(color)),
        "TextXAlignment": x_align,
        "TextYAlignment": 1,
        "TextWrapped": wrapped,
        "TextTruncate": truncate,
        "TextTransparency": 0.0,
        "TextStrokeTransparency": 1.0,
        "FontFace": ("raw", FONT),
    }


# ---------------------------------------------------------------------------
# menu buttons (StarterGui/Buttons)
# ---------------------------------------------------------------------------

def menu_buttons(b, gd):
    """One TextButton per menu, at an explicit slot.

    Slots are hand-picked rather than computed from a grid: the base HUD already
    occupies most of the screen (2xCash sits at x 0.225+, y 0.899+), so a third
    grid column would land on top of it. tools/tests/test_content.py asserts there
    is a slot for every menu and verify.py asserts nothing overlaps.
    """
    ui = gd["ui"]
    xs, ys = ui["menuGridX"], ui["menuGridY"]
    slots = ui.get("menuSlots") or []
    w, h = ui["buttonSize"]
    out = []
    for i, menu in enumerate(gd["menus"]):
        if i < len(slots):
            x, y = slots[i]
        else:
            # Past the end of the slot list: fall back to the grid so a new menu
            # is still visible (and overlapping) rather than silently missing.
            x = xs[i % len(xs)]
            y = ys[i // len(xs)]
        props = {
            "Position": ("UDim2", (x, 0, y, 0)),
            "Size": ("UDim2", (w, 0, h, 0)),
            "AnchorPoint": ("Vector2", (0, 0)),
            "BackgroundColor3": ("Color3", tuple(ui["panelColor"])),
            "BackgroundTransparency": 0.05,
            "BorderSizePixel": 0,
            "Visible": True,
            "ZIndex": 2,
            "Active": True,
            "Selectable": True,
            "AutoButtonColor": True,
            "ClipsDescendants": False,
            "LayoutOrder": 100 + i,
        }
        props.update(text_overrides(menu["label"], size=14, x_align=2, truncate=0))
        children = (ui_corner(b, 8, depth=D + 1)
                    + ui_stroke(b, menu["color"], 2, 0, depth=D + 1)
                    + text_size(b, 18, 8, depth=D + 1))
        out.append(b.item("TextButton", menu["name"], props, children=children, depth=D)[0])
    return "".join(out)


# ---------------------------------------------------------------------------
# menu frames (StarterGui/Frames)
# ---------------------------------------------------------------------------

def row_template(b, ui, depth=D + 2):
    """The row every menu clones. Visible = false: it is a template, not content."""
    props = {
        "Position": ("UDim2", (0, 0, 0, 0)),
        "Size": ("UDim2", (1, -10, 0, int(ui["rowHeight"]))),
        "BackgroundColor3": ("Color3", tuple(ui["rowColor"])),
        "BackgroundTransparency": 0.1,
        "BorderSizePixel": 0,
        "Visible": False,
        "ZIndex": 2,
        "AutoButtonColor": True,
        "LayoutOrder": 0,
        "ClipsDescendants": False,
    }
    props.update(text_overrides("Row", size=17, x_align=0, truncate=1))

    info_props = {
        "BackgroundTransparency": 1.0,
        "Position": ("UDim2", (0.55, -12, 0, 0)),
        "Size": ("UDim2", (0.45, 0, 1, 0)),
        "Visible": True,
        "ZIndex": 3,
    }
    info_props.update(text_overrides("", size=15, x_align=2, color=(170, 200, 255)))

    sub_props = {
        "BackgroundTransparency": 1.0,
        "Position": ("UDim2", (0, 12, 1, -26)),
        "Size": ("UDim2", (1, -24, 0, 18)),
        "Visible": True,
        "ZIndex": 3,
    }
    sub_props.update(text_overrides("", size=13, x_align=0, color=(150, 160, 185)))

    # Optional progress bar, hidden by default: Quests shows it, the other menus
    # leave it alone. Living in the shared template means it costs nothing and any
    # menu can use it later.
    bar_props = {
        "BackgroundColor3": ("Color3", (16, 18, 26)),
        "BackgroundTransparency": 0.15,
        "BorderSizePixel": 0,
        "Position": ("UDim2", (0, 12, 1, -8)),
        "Size": ("UDim2", (1, -24, 0, 6)),
        "Visible": False,
        "ZIndex": 3,
        "ClipsDescendants": True,
    }
    fill_props = {
        "BackgroundColor3": ("Color3", tuple(ui["accent"])),
        "BackgroundTransparency": 0.0,
        "BorderSizePixel": 0,
        "Position": ("UDim2", (0, 0, 0, 0)),
        "Size": ("UDim2", (0, 0, 1, 0)),
        "Visible": True,
        "ZIndex": 4,
    }

    children = (
        ui_corner(b, 8, depth=depth + 1)
        + ui_stroke(b, ui["accent"], 1.5, 0.4, depth=depth + 1)
        + ui_padding(b, 12, 12, 0, 0, depth=depth + 1)
        + b.item("TextLabel", "Info", info_props, depth=depth + 1)[0]
        + b.item("TextLabel", "Subtitle", sub_props, depth=depth + 1)[0]
        + b.item("Frame", "Bar", bar_props,
                 children=(ui_corner(b, 3, "BarCorner", depth=depth + 2)
                           + b.item("Frame", "Fill", fill_props,
                                    children=ui_corner(b, 3, depth=depth + 3),
                                    depth=depth + 2)[0]),
                 depth=depth + 1)[0]
    )
    return b.item("TextButton", "RowTemplate", props, children=children, depth=depth)[0]


def section_template(b, ui, depth=D + 2):
    props = {
        "Size": ("UDim2", (1, -10, 0, 30)),
        "BackgroundColor3": ("Color3", tuple(ui["titleColor"])),
        "BackgroundTransparency": 0.25,
        "BorderSizePixel": 0,
        "Visible": False,
        "ZIndex": 2,
        "LayoutOrder": 0,
    }
    props.update(text_overrides("Section", size=16, x_align=0, color=(200, 210, 235)))
    children = (ui_corner(b, 8, depth=depth + 1)
                + ui_padding(b, 12, 12, 0, 0, depth=depth + 1))
    return b.item("TextLabel", "SectionTemplate", props, children=children, depth=depth)[0]


def menu_frames(b, gd):
    ui = gd["ui"]
    fw, fh = ui["frameSize"]
    out = []
    for menu in gd["menus"]:
        name = menu["name"]
        accent = menu["color"]
        has_status = bool(menu.get("status"))
        has_bar = bool(menu.get("commandBar"))
        has_claim_all = bool(menu.get("claimAll"))

        list_top = 0.245 if has_status else 0.14
        if has_bar:
            list_top = 0.245
        list_h = round(0.96 - list_top, 3)

        frame_props = {
            "AnchorPoint": ("Vector2", (0.5, 0.5)),
            "Position": ("UDim2", (0.5, 0, 0.5, 0)),
            "Size": ("UDim2", (fw, 0, fh, 0)),
            "BackgroundColor3": ("Color3", tuple(ui["panelColor"])),
            "BackgroundTransparency": 0.02,
            "BorderSizePixel": 0,
            "Visible": False,
            "ZIndex": 1,
            "ClipsDescendants": False,
            "Active": False,
            "Selectable": False,
        }

        title_props = {
            "Position": ("UDim2", (0.03, 0, 0.02, 0)),
            "Size": ("UDim2", (0.94, 0, 0.1, 0)),
            "BackgroundColor3": ("Color3", tuple(ui["titleColor"])),
            "BackgroundTransparency": 0.15,
            "BorderSizePixel": 0,
            "Visible": True,
            "ZIndex": 3,
        }
        title_props.update(text_overrides(name, size=26, scaled=True, x_align=2))

        list_props = {
            "Position": ("UDim2", (0.03, 0, list_top, 0)),
            "Size": ("UDim2", (0.94, 0, list_h, 0)),
            "BackgroundColor3": ("Color3", tuple(ui["listColor"])),
            "BackgroundTransparency": 0.35,
            "BorderSizePixel": 0,
            "ClipsDescendants": True,
            "Visible": True,
            "ZIndex": 1,
            "AutomaticCanvasSize": 2,
            "CanvasSize": ("UDim2", (0, 0, 0, 0)),
            "ScrollingDirection": 2,
            "ScrollingEnabled": True,
            "ScrollBarThickness": 8,
            "ScrollBarImageColor3": ("Color3", tuple(accent)),
            "ScrollBarImageTransparency": 0.0,
            "VerticalScrollBarInset": 1,
            "Active": True,
            "Selectable": True,
        }

        close_props = {
            "Position": ("UDim2", (1, -34, 0, 4)),
            "Size": ("UDim2", (0, 30, 0, 30)),
            "BackgroundColor3": ("Color3", (190, 60, 60)),
            "BackgroundTransparency": 0.0,
            "BorderSizePixel": 0,
            "Visible": True,
            "ZIndex": 4,
            "AutoButtonColor": True,
        }
        close_props.update(text_overrides("X", size=20, scaled=True, x_align=2, wrapped=False))

        children = (
            ui_corner(b, 14, depth=D + 1)
            + ui_stroke(b, accent, 2, 0, depth=D + 1)
            + b.item("TextLabel", "Title", title_props,
                     children=text_size(b, 30, 12, depth=D + 2), depth=D + 1)[0]
        )

        if has_status:
            # A claim-all button shares this line, so the status text gives way.
            status_width = 0.66 if has_claim_all else 0.94
            status_props = {
                "Position": ("UDim2", (0.03, 0, 0.135, 0)),
                "Size": ("UDim2", (status_width, 0, 0.085, 0)),
                "BackgroundColor3": ("Color3", (18, 20, 30)),
                "BackgroundTransparency": 0.35,
                "BorderSizePixel": 0,
                "Visible": True,
                "ZIndex": 2,
            }
            status_props.update(text_overrides("", size=18, scaled=True, x_align=2,
                                               color=(255, 220, 120)))
            children += b.item("TextLabel", "Status", status_props,
                               children=text_size(b, 20, 10, depth=D + 2), depth=D + 1)[0]

        if has_claim_all:
            claim_props = {
                "Position": ("UDim2", (0.71, 0, 0.135, 0)),
                "Size": ("UDim2", (0.26, 0, 0.085, 0)),
                "BackgroundColor3": ("Color3", tuple(accent)),
                "BackgroundTransparency": 0.0,
                "BorderSizePixel": 0,
                "Visible": True,
                "ZIndex": 4,
                "AutoButtonColor": True,
            }
            claim_props.update(text_overrides("Claim All", size=16, scaled=True, x_align=2))
            children += b.item("TextButton", "ClaimAll", claim_props,
                               children=(ui_corner(b, 8, depth=D + 2)
                                         + text_size(b, 18, 9, depth=D + 2)),
                               depth=D + 1)[0]

        if has_bar:
            bar_props = {
                "Position": ("UDim2", (0.03, 0, 0.14, 0)),
                "Size": ("UDim2", (0.94, 0, 0.085, 0)),
                "BackgroundColor3": ("Color3", (18, 20, 30)),
                "BackgroundTransparency": 0.15,
                "BorderSizePixel": 0,
                "Visible": True,
                "ZIndex": 5,
            }
            box_props = {
                "BackgroundTransparency": 1.0,
                "Position": ("UDim2", (0, 10, 0, 0)),
                "Size": ("UDim2", (1, -100, 1, 0)),
                "Visible": True,
                "ZIndex": 6,
                "ClearTextOnFocus": False,
                "PlaceholderText": "type a command, then Enter",
                "PlaceholderColor3": ("Color3", (120, 128, 150)),
                "TextEditable": True,
            }
            box_props.update(text_overrides("", size=15, x_align=0))
            send_props = {
                "Position": ("UDim2", (1, -84, 0.12, 0)),
                "Size": ("UDim2", (0, 74, 0.76, 0)),
                "BackgroundColor3": ("Color3", tuple(accent)),
                "BackgroundTransparency": 0.0,
                "BorderSizePixel": 0,
                "Visible": True,
                "ZIndex": 6,
                "AutoButtonColor": True,
            }
            send_props.update(text_overrides("Run", size=15, scaled=True, x_align=2))
            children += b.item("Frame", "CommandBar", bar_props,
                               children=(ui_corner(b, 8, depth=D + 2)
                                         + b.item("TextBox", "Input", box_props, depth=D + 2)[0]
                                         + b.item("TextButton", "Send", send_props,
                                                  children=ui_corner(b, 6, depth=D + 3),
                                                  depth=D + 2)[0]),
                               depth=D + 1)[0]

        children += b.item("ScrollingFrame", "List", list_props,
                           children=(ui_list_layout(b, 6, 2, 0, 0, depth=D + 2)
                                     + row_template(b, ui, D + 2)
                                     + section_template(b, ui, D + 2)),
                           depth=D + 1)[0]

        children += b.item("TextButton", "Close", close_props,
                           children=(ui_corner(b, 8, depth=D + 2)
                                     + text_size(b, 22, 10, depth=D + 2)),
                           depth=D + 1)[0]

        out.append(b.item("Frame", name, frame_props, children=children, depth=D)[0])
    return "".join(out)


# ---------------------------------------------------------------------------
# kill feed and zone warning (StarterGui)
# ---------------------------------------------------------------------------

def killfeed(b, gd):
    """StarterGui/KillFeed: top-centre strip that reports who ate whom.

    Top centre is the one region of the screen neither Roblox core UI (chat
    top-left, player list top-right) nor this game's HUD uses.
    """
    ui = gd["ui"]
    entry_props = {
        "BackgroundColor3": ("Color3", (16, 18, 26)),
        "BackgroundTransparency": 0.2,
        "BorderSizePixel": 0,
        "Size": ("UDim2", (1, 0, 0, 26)),
        "Visible": False,          # template
        "ZIndex": 2,
        "LayoutOrder": 0,
        "ClipsDescendants": False,
    }
    entry_props.update(text_overrides("", size=15, x_align=0, color=(235, 240, 255)))

    entries_props = {
        "AnchorPoint": ("Vector2", (0.5, 0)),
        "BackgroundColor3": ("Color3", (0, 0, 0)),
        "BackgroundTransparency": 1.0,
        "BorderSizePixel": 0,
        "Position": ("UDim2", (0.5, 0, 0.06, 0)),
        "Size": ("UDim2", (0, 420, 0, 160)),
        "Visible": True,
        "ZIndex": 1,
        "ClipsDescendants": False,
    }

    entries = b.item("Frame", "Entries", entries_props,
                     children=(ui_list_layout(b, 4, 2, 0, 0, depth=D + 2)
                               + b.item("TextLabel", "Entry", entry_props,
                                        children=(ui_corner(b, 6, depth=D + 3)
                                                  + ui_padding(b, 10, 10, 0, 0, depth=D + 3)
                                                  + text_size(b, 17, 9, depth=D + 3)),
                                        depth=D + 2)[0]),
                     depth=D + 1)[0]

    gui_props = {
        "DisplayOrder": 6,
        "Enabled": True,
        "ResetOnSpawn": False,     # one client script: a reset would strand it
        "ScreenInsets": 1,         # CoreUISafeInsets
        "ZIndexBehavior": 1,
    }
    return b.item("ScreenGui", "KillFeed", gui_props, children=entries, depth=D)[0]


def zonewarn(b, gd):
    """StarterGui/ZoneWarn: red edge + reason when standing in a locked zone.

    The server already refuses the food and the teleport; this is the part that
    stops the gate feeling arbitrary.
    """
    label_props = {
        "AnchorPoint": ("Vector2", (0.5, 0)),
        "BackgroundColor3": ("Color3", (16, 18, 26)),
        "BackgroundTransparency": 0.15,
        "BorderSizePixel": 0,
        "Position": ("UDim2", (0.5, 0, 0.24, 0)),
        "Size": ("UDim2", (0, 460, 0, 44)),
        "Visible": True,
        "ZIndex": 3,
    }
    label_props.update(text_overrides("", size=19, scaled=True, x_align=2, color=(255, 170, 150)))

    tint_props = {
        "BackgroundColor3": ("Color3", (0, 0, 0)),
        "BackgroundTransparency": 1.0,
        "BorderSizePixel": 0,
        "Position": ("UDim2", (0, 0, 0, 0)),
        "Size": ("UDim2", (1, 0, 1, 0)),
        "Visible": False,
        "ZIndex": 2,
        "ClipsDescendants": False,
    }

    tint = b.item("Frame", "Tint", tint_props,
                  children=(b.item("UIStroke", "UIStroke", {
                                      "ApplyStrokeMode": 0,     # Border
                                      "Color": ("Color3", (235, 70, 70)),
                                      "Thickness": 16.0,
                                      "Transparency": 0.35,
                                      "Enabled": True,
                                      "LineJoinMode": 2,
                                  }, depth=D + 2)[0]
                            + b.item("TextLabel", "Label", label_props,
                                     children=(ui_corner(b, 10, depth=D + 3)
                                               + text_size(b, 22, 10, depth=D + 3)),
                                     depth=D + 2)[0]),
                  depth=D + 1)[0]

    gui_props = {
        "DisplayOrder": 7,
        "Enabled": True,
        "ResetOnSpawn": False,
        "ScreenInsets": 0,        # None: the edge tint has to reach the real edge
        "ZIndexBehavior": 1,
    }
    return b.item("ScreenGui", "ZoneWarn", gui_props, children=tint, depth=D)[0]


# ---------------------------------------------------------------------------
# notifier (ReplicatedFirst/Client)
# ---------------------------------------------------------------------------

def notifier(b, gd):
    ui = gd["ui"]
    kinds = gd["notifier"]["kinds"]

    toast_props = {
        "Size": ("UDim2", (1, 0, 0, 34)),
        "BackgroundColor3": ("Color3", (18, 20, 30)),
        "BackgroundTransparency": 0.05,
        "BorderSizePixel": 0,
        "Visible": False,
        "ZIndex": 6,
        "LayoutOrder": 0,
        "ClipsDescendants": False,
    }
    toast_props.update(text_overrides("", size=16, scaled=True, x_align=2, wrapped=True))

    container_props = {
        "AnchorPoint": ("Vector2", (0.5, 1)),
        "Position": ("UDim2", (0.5, 0, 0.72, 0)),
        "Size": ("UDim2", (0, 420, 0, 220)),
        "BackgroundTransparency": 1.0,
        "BorderSizePixel": 0,
        "Visible": True,
        "ZIndex": 5,
        "ClipsDescendants": False,
    }

    gui_props = {
        "Enabled": True,
        "ResetOnSpawn": False,
        "ZIndexBehavior": 1,
        "DisplayOrder": 20,
        "ClipToDeviceSafeArea": True,
    }

    children = (
        ui_list_layout(b, 6, 2, 1, 2, depth=D + 2)      # LayoutOrder, centred, bottom aligned
        + b.item("TextLabel", "Toast", toast_props,
                 children=(ui_corner(b, 8, depth=D + 3)
                           + ui_stroke(b, kinds["info"], 1.5, 0.3, depth=D + 3)
                           + ui_padding(b, 14, 14, 0, 0, depth=D + 3)
                           + text_size(b, 20, 10, depth=D + 3)),
                 depth=D + 2)[0]
    )
    toasts = b.item("Frame", "Toasts", container_props, children=children, depth=D + 1)[0]

    # Per-kind accent colours ship next to the template so the notifier does not
    # hard-code them.
    kind_colors = "".join(
        color(b, label + "Color", kinds[key], depth=D + 1)
        for label, key in (("Info", "info"), ("Good", "good"), ("Bad", "bad")))

    return b.item("ScreenGui", "Notifier", gui_props, children=toasts + kind_colors, depth=D)[0]


# ---------------------------------------------------------------------------
# zones (Workspace/Zones)
# ---------------------------------------------------------------------------

def zone_req_text(zone):
    if zone.get("reqRebirth"):
        n = zone["reqRebirth"]
        return "Requires %d Rebirth%s" % (n, "" if n == 1 else "s")
    if zone.get("reqSize"):
        return "Requires Size %d" % zone["reqSize"]
    return "Unlocked"


def zones(b, gd):
    settings = gd["settings"]
    floor_y = float(settings["ZoneFloorY"])
    thickness = 1.0
    out = []
    for z in gd["zones"]:
        cx, cz = z["center"]
        r = z["radius"]
        cy = floor_y - thickness / 2.0

        part_props = {
            "shape": 1,          # Enum.PartType.Block
            "Anchored": True,
            "CanCollide": True,
            "CanQuery": True,
            "CanTouch": False,
            "CastShadow": False,
            "Locked": False,
            "Transparency": 0.0,
            "Reflectance": 0.0,
            "Color3uint8": ("Color3uint8", tuple(z["color"])),
            "CFrame": ("CoordinateFrame", (cx, cy, cz)),
            "size": ("Vector3", (r * 2, thickness, r * 2)),
        }

        sign_text = "%s\n%s cubes  |  %s" % (z["name"], z["rarity"], zone_req_text(z))
        label_props = {
            "Size": ("UDim2", (1, 0, 1, 0)),
            "BackgroundColor3": ("Color3", (10, 10, 16)),
            "BackgroundTransparency": 0.35,
            "BorderSizePixel": 0,
            "Visible": True,
            "ZIndex": 2,
        }
        label_props.update(text_overrides(sign_text, size=20, scaled=True, x_align=2, wrapped=True))

        sign = b.item("BillboardGui", "Sign", {
            "AlwaysOnTop": False,
            "Enabled": True,
            "ClipsDescendants": False,
            "StudsOffset": ("Vector3", (0, 12, 0)),
            "LightInfluence": 0.0,
            "Size": ("UDim2", (0, 300, 0, 90)),
            "MaxDistance": 900.0,
            "ResetOnSpawn": False,
            "ZIndexBehavior": 1,
        }, children=b.item("TextLabel", "Label", label_props,
                           children=text_size(b, 26, 10, depth=D + 4), depth=D + 3)[0],
            depth=D + 2)[0]

        values = (integer(b, "Id", z["id"], D + 2)
                  + string(b, "Rarity", z["rarity"], D + 2)
                  + num(b, "ReqSize", z.get("reqSize", 0), D + 2)
                  + num(b, "ReqRebirth", z.get("reqRebirth", 0), D + 2)
                  + color(b, "Color", z["color"], D + 2))

        out.append(b.item("Part", z["name"], part_props,
                          children=values + sign, depth=D + 1)[0])

    return folder(b, "Zones", "".join(out), D)


# ---------------------------------------------------------------------------
# entry point
# ---------------------------------------------------------------------------

def load(src_root="src"):
    with open(os.path.join(src_root, "gamedata.json"), encoding="utf-8") as f:
        return json.load(f)


def build(b, gd):
    """All content XML, keyed by the parent path it belongs under."""
    return {
        "ReplicatedStorage": gamedata(b, gd),
        "ReplicatedStorage/Events": events(b, gd),
        "StarterGui/Buttons": menu_buttons(b, gd),
        "StarterGui/Frames": menu_frames(b, gd),
        "StarterGui": killfeed(b, gd) + zonewarn(b, gd),
        "Workspace": zones(b, gd),
    }


if __name__ == "__main__":
    import sys
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from rbxlx import Builder
    import xml.etree.ElementTree as ET
    data = open("base_cube.rbxlx", encoding="utf-8", errors="replace").read()
    b = Builder(data)
    gd = load()
    chunks = build(b, gd)
    chunks["ReplicatedFirst/Client"] = notifier(b, gd)
    total = 0
    for parent, xml in chunks.items():
        ET.fromstring("<roblox>" + xml + "</roblox>")
        n = xml.count("<Item ")
        total += n
        print("%-28s %3d instances %8d bytes  XML ok" % (parent, n, len(xml)))
    print("total generated instances:", total)
