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
  Workspace/Zones              one arena Model per zone - floor slab, four walls,
                               a sign and the zone's id, rarity and requirements
                               as value children. Move or resize an arena in
                               Studio and the game follows: it reads the map, not
                               a config.

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
    # A Color3Value carries its colour in the property called "Value"; writing it
    # under any other name leaves the value at its black default.
    return b.bare_item("Color3Value", name, [("Color3", "Value", tuple(rgb))], depth=depth)[0]


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


def tabs(gd):
    """The HUD tabs, in order (gd.tabs.items)."""
    return list((gd.get("tabs") or {}).get("items") or [])


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

    # Which menu each tab row opens. The launcher panels live in StarterGui/
    # Frames; this is the data they read, so retargeting a row - or moving it to
    # another tab - is a Studio edit. A target that starts with "@" is an action
    # rather than a frame (Tabs.lua knows those).
    tab_sections = ""
    for tab in tabs(gd):
        entries = ""
        for order, entry in enumerate(tab["entries"], start=1):
            entries += folder(b, entry["label"],
                              string(b, "Target", entry["target"], D + 4)
                              + string(b, "Sub", entry.get("sub", ""), D + 4)
                              + num(b, "Order", order, D + 4)
                              + color(b, "Color", entry.get("color", tab["color"]), D + 4),
                              D + 3)
        tab_sections += folder(b, tab["name"], entries, D + 2)
    sections.append(folder(b, "Tabs", tab_sections, D + 1))

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

def ui_corner(b, radius=8, name="UICorner", depth=D + 2, scale=False):
    """radius is pixels unless scale=True, which is how the shipped panels round."""
    udim = (radius, 0) if scale else (0, radius)
    return b.item("UICorner", name, {
        "TopLeftRadius": ("UDim", udim),
        "TopRightRadius": ("UDim", udim),
        "BottomLeftRadius": ("UDim", udim),
        "BottomRightRadius": ("UDim", udim),
    }, depth=depth)[0]


def ui_aspect(b, ratio, depth=D + 2):
    """Square-ish, width driven: the constraint every shipped HUD button carries."""
    return b.item("UIAspectRatioConstraint", "UIAspectRatioConstraint", {
        "AspectRatio": float(ratio),
        "AspectType": 0,       # FitWithinMaxSize
        "DominantAxis": 0,     # Width
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


def font_face(url, weight):
    return ('<Font name="FontFace"><Family><url>%s</url></Family>'
            '<Weight>%d</Weight><Style>Normal</Style></Font>' % (url, int(weight)))


# The two families the shipped HUD uses: the display face behind every button and
# panel title, and FredokaOne behind row text (Frames/Rewards, UpdateLog/template).
FONT = font_face("rbxassetid://12187365977", 700)
FONT_ALT = font_face("rbxasset://fonts/families/FredokaOne.json", 400)


def fonts(ui):
    """FontFace XML for the families named in gamedata.json, with shipped defaults."""
    spec = ui.get("fonts") or {}
    return {
        "main": ("raw", font_face(spec.get("main", "rbxassetid://12187365977"),
                                  spec.get("mainWeight", 700))),
        "alt": ("raw", font_face(spec.get("alt", "rbxasset://fonts/families/FredokaOne.json"),
                                 spec.get("altWeight", 400))),
    }


def text_overrides(text, size=17, scaled=False, x_align=0, wrapped=False, rich=True,
                   color=(255, 255, 255), truncate=1, font=None):
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
        # Outlines come from a UIStroke child, the way the shipped UI does it.
        "TextStrokeTransparency": 1.0,
        "FontFace": font or ("raw", FONT),
    }


# ---------------------------------------------------------------------------
# tab buttons (StarterGui/Buttons)
# ---------------------------------------------------------------------------

def tab_buttons(b, gd):
    """Three tab buttons, built the way the shipped HUD builds its own buttons.

    StarterGui/Buttons/Music is the model: a coloured rounded rect with a black
    outline, the game's button plate as its Image (which ships invisible, so the
    body colour shows), an ImageLabel icon that UiModule.Animate wiggles on hover
    and a caption hanging underneath. Nothing here is a new visual idea.

    Each tab takes a slot the shipped Invite / Music / Favorite buttons used to
    occupy (those buttons are gone, so nothing overlaps), and each opens a
    launcher panel whose rows open the real menus - see gd.tabs.
    """
    ui = gd["ui"]
    F = fonts(ui)
    w, h = ui["buttonSize"]
    corner = ui.get("buttonCorner", 8)
    stroke_rgb = ui.get("buttonStroke", [0, 0, 0])
    stroke_w = ui.get("buttonStrokeWidth", 4.5)
    icon_size = ui.get("iconSize", 0.773333311)
    icon_inset = ui.get("iconInset", 0.106666461)
    cap_w, cap_h = ui.get("captionSize", [2.66666675, 0.306666672])
    cap_x, cap_y = ui.get("captionPosition", [-0.838627338, 0.890537024])
    plate = ui.get("buttonPlate", "")

    out = []
    for i, tab in enumerate(tabs(gd)):
        # No explicit slot: stack down the left column the shipped buttons used,
        # at their spacing, so a fourth tab is still visible (and verify.py can
        # still prove it does not overlap anything).
        x, y = tab.get("slot") or [0.027524806559085846, 0.364469975233078 + 0.1363 * i]

        props = {
            "Position": ("UDim2", (x, 0, y, 0)),
            "Size": ("UDim2", (w, 0, h, 0)),
            "AnchorPoint": ("Vector2", (0, 0)),
            "BackgroundColor3": ("Color3", tuple(tab["color"])),
            "BackgroundTransparency": 0.0,
            "BorderSizePixel": 0,
            "Image": ("Content", "<url>%s</url>" % plate) if plate else ("Content", "<null></null>"),
            "ImageColor3": ("Color3", (255, 255, 255)),
            "ImageTransparency": 1.0,   # as shipped: the plate is there, the body shows
            "ScaleType": 0,
            "Visible": True,
            "ZIndex": 1,
            "Active": True,
            "Selectable": True,
            "AutoButtonColor": True,
            "ClipsDescendants": False,
            "LayoutOrder": 100 + i,
        }

        icon_props = {
            "Position": ("UDim2", (icon_inset, 0, icon_inset, 0)),
            "Size": ("UDim2", (icon_size, 0, icon_size, 0)),
            "BackgroundTransparency": 1.0,
            "BorderSizePixel": 0,
            "Image": ("Content", "<url>%s</url>" % tab["icon"]),
            "ImageColor3": ("Color3", (255, 255, 255)),
            "ImageTransparency": 0.0,
            "ScaleType": 0,
            "Visible": True,
            "ZIndex": 1,
            "LayoutOrder": 0,
        }

        cap_props = {
            "Position": ("UDim2", (cap_x, 0, cap_y, 0)),
            "Size": ("UDim2", (cap_w, 0, cap_h, 0)),
            "BackgroundTransparency": 1.0,
            "BorderSizePixel": 0,
            "Visible": True,
            "ZIndex": 1,
            "LayoutOrder": 0,
        }
        cap_props.update(text_overrides(tab.get("label", tab["name"]), size=14, scaled=True, x_align=2,
                                        wrapped=True, truncate=0, color=(255, 255, 255),
                                        font=F["main"]))

        children = (
            ui_corner(b, corner, depth=D + 1)
            + ui_stroke(b, stroke_rgb, stroke_w, 0, depth=D + 1)
            + b.item("ImageLabel", "ImageLabel", icon_props, depth=D + 1)[0]
            + b.item("TextLabel", "TextLabel", cap_props,
                     children=(ui_stroke(b, stroke_rgb, 3, 0, depth=D + 2)
                               + text_size(b, ui.get("captionMaxText", 23), 1, depth=D + 2)),
                     depth=D + 1)[0]
            + ui_aspect(b, ui.get("buttonAspect", 0.995738626), depth=D + 1)
        )
        out.append(b.item("ImageButton", tab["name"], props, children=children, depth=D)[0])
    return "".join(out)


# ---------------------------------------------------------------------------
# menu frames (StarterGui/Frames)
# ---------------------------------------------------------------------------

def row_template(b, ui, depth=D + 2):
    """The row every menu clones, in the shipped list style.

    Frames/Rewards/Rewards/Reward1 is the model: a cyan block, black outline,
    chunky FredokaOne text with its own outline. Visible = false - it is a
    template, not content. MenuUi.addRow clones it and only ever touches Info,
    Subtitle, Bar/Fill and the row's own UIStroke, so those names are a contract.
    """
    F = fonts(ui)
    stroke = ui.get("rowStroke", [0, 0, 0])
    props = {
        "Position": ("UDim2", (0, 0, 0, 0)),
        "Size": ("UDim2", (1, -14, 0, int(ui["rowHeight"]))),
        "BackgroundColor3": ("Color3", tuple(ui["rowColor"])),
        "BackgroundTransparency": 0.0,
        "BorderSizePixel": 0,
        "Visible": False,
        "ZIndex": 2,
        "AutoButtonColor": True,
        "LayoutOrder": 0,
        "ClipsDescendants": False,
    }
    props.update(text_overrides("", size=17, x_align=0, truncate=1, font=F["alt"]))

    info_props = {
        "AnchorPoint": ("Vector2", (0, 0.5)),
        "BackgroundTransparency": 1.0,
        "BorderSizePixel": 0,
        "Position": ("UDim2", (0.03, 0, 0.47, 0)),
        "Size": ("UDim2", (0.56, 0, 0.6, 0)),
        "Visible": True,
        "ZIndex": 3,
        "LayoutOrder": 0,
    }
    info_props.update(text_overrides("", size=18, scaled=True, x_align=0, truncate=1,
                                     color=tuple(ui["rowText"]), font=F["alt"]))

    sub_props = {
        "AnchorPoint": ("Vector2", (0, 0.5)),
        "BackgroundTransparency": 1.0,
        "BorderSizePixel": 0,
        "Position": ("UDim2", (0.6, 0, 0.47, 0)),
        "Size": ("UDim2", (0.37, 0, 0.5, 0)),
        "Visible": True,
        "ZIndex": 3,
        "LayoutOrder": 0,
    }
    sub_props.update(text_overrides("", size=15, scaled=True, x_align=2, truncate=1,
                                    color=tuple(ui["subText"]), font=F["alt"]))

    # Optional progress bar, shipped hidden inside the template: Quests shows it,
    # the other menus leave it alone.
    bar_props = {
        "AnchorPoint": ("Vector2", (0.5, 1)),
        "BackgroundColor3": ("Color3", tuple(ui["barTrack"])),
        "BackgroundTransparency": 0.0,
        "BorderSizePixel": 0,
        "Position": ("UDim2", (0.5, 0, 1, -5)),
        "Size": ("UDim2", (0.94, 0, 0.11, 0)),
        "Visible": False,
        "ZIndex": 3,
        "ClipsDescendants": True,
        "LayoutOrder": 0,
    }
    fill_props = {
        "BackgroundColor3": ("Color3", tuple(ui["barFill"])),
        "BackgroundTransparency": 0.0,
        "BorderSizePixel": 0,
        "Position": ("UDim2", (0, 0, 0, 0)),
        "Size": ("UDim2", (0, 0, 1, 0)),
        "Visible": True,
        "ZIndex": 4,
        "LayoutOrder": 0,
    }

    children = (
        ui_corner(b, ui.get("rowCorner", 8), depth=depth + 1)
        + ui_stroke(b, stroke, ui.get("rowStrokeWidth", 3), 0, depth=depth + 1)
        + b.item("TextLabel", "Info", info_props,
                 children=ui_stroke(b, stroke, 2.5, 0, depth=depth + 2),
                 depth=depth + 1)[0]
        + b.item("TextLabel", "Subtitle", sub_props,
                 children=ui_stroke(b, stroke, 2.5, 0, depth=depth + 2),
                 depth=depth + 1)[0]
        + b.item("Frame", "Bar", bar_props,
                 children=(ui_corner(b, 4, "BarCorner", depth=depth + 2)
                           + ui_stroke(b, stroke, 2, 0, depth=depth + 2)
                           + b.item("Frame", "Fill", fill_props,
                                    children=ui_corner(b, 4, depth=depth + 3),
                                    depth=depth + 2)[0]),
                 depth=depth + 1)[0]
    )
    return b.item("TextButton", "RowTemplate", props, children=children, depth=depth)[0]


def section_template(b, ui, depth=D + 2):
    """A purple banner between groups of rows - the game's own accent colour."""
    F = fonts(ui)
    props = {
        "Position": ("UDim2", (0, 0, 0, 0)),
        "Size": ("UDim2", (1, -14, 0, 34)),
        "BackgroundColor3": ("Color3", tuple(ui["sectionColor"])),
        "BackgroundTransparency": 0.0,
        "BorderSizePixel": 0,
        "Visible": False,
        "ZIndex": 2,
        "LayoutOrder": 0,
        "ClipsDescendants": False,
    }
    props.update(text_overrides("Section", size=17, scaled=True, x_align=2,
                                color=tuple(ui["sectionText"]), font=F["main"]))
    children = (ui_corner(b, ui.get("rowCorner", 8), depth=depth + 1)
                + ui_stroke(b, ui.get("rowStroke", [0, 0, 0]), 3, 0, depth=depth + 1)
                + text_size(b, 24, 10, depth=depth + 1))
    return b.item("TextLabel", "SectionTemplate", props, children=children, depth=depth)[0]


def menu_frames(b, gd):
    """One panel per menu - and per tab - styled like Frames/UpdateLog, Frames/Codes.

    White panel, black outline, the title straddling the top edge in the game's
    purple, a transparent scrolling list of cyan rows. Child names (Title, List,
    RowTemplate, SectionTemplate, Close, and Status/ClaimAll where the menu asks
    for them) are the contract MenuUi and the menu modules code against.

    Panels are big on purpose (ui.frameSize): rows, progress bars and the
    scrollbar all have to fit without clipping. A tab launcher uses the compact
    ui.tabFrameSize with taller rows, so its three tiles read as tiles.
    """
    stroke = gd["ui"].get("panelStroke", [0, 0, 0])
    specs = [(menu, gd["ui"]["frameSize"], gd["ui"]["rowHeight"]) for menu in gd["menus"]]
    specs += [(tab, gd["ui"]["tabFrameSize"], gd["ui"]["tabRowHeight"]) for tab in tabs(gd)]
    out = []
    for menu, frame_size, row_height in specs:
        # The row and section templates take their height from ui, so hand them a
        # copy that carries this panel's row height.
        ui = dict(gd["ui"], rowHeight=row_height)
        F = fonts(ui)
        fw, fh = frame_size
        name = menu["name"]
        accent = menu["color"]
        has_status = bool(menu.get("status"))
        has_bar = bool(menu.get("commandBar"))
        has_claim_all = bool(menu.get("claimAll"))

        list_top = 0.2 if (has_status or has_bar) else 0.1
        list_h = round(0.97 - list_top, 3)

        frame_props = {
            "AnchorPoint": ("Vector2", (0.5, 0.5)),
            "Position": ("UDim2", (0.5, 0, 0.5, 0)),
            "Size": ("UDim2", (fw, 0, fh, 0)),
            "BackgroundColor3": ("Color3", tuple(ui["panelColor"])),
            "BackgroundTransparency": 0.0,
            "BorderSizePixel": 0,
            "Visible": False,
            "ZIndex": 1,
            "ClipsDescendants": False,
            "Active": False,
            "Selectable": False,
            "LayoutOrder": 0,
        }

        tw, th = ui.get("titleSize", [0.4, 0.115])
        title_props = {
            "AnchorPoint": ("Vector2", (0.5, 0.5)),
            "Position": ("UDim2", (0.5, 0, 0, 0)),
            "Size": ("UDim2", (tw, 0, th, 0)),
            "BackgroundTransparency": 1.0,
            "BorderSizePixel": 0,
            "Visible": True,
            "ZIndex": 4,
            "LayoutOrder": 0,
        }
        title_props.update(text_overrides(name, size=26, scaled=True, x_align=2,
                                          color=tuple(ui["titleColor"]), font=F["main"]))

        list_props = {
            "AnchorPoint": ("Vector2", (0.5, 0)),
            "Position": ("UDim2", (0.5, 0, list_top, 0)),
            "Size": ("UDim2", (0.94, 0, list_h, 0)),
            "BackgroundColor3": ("Color3", tuple(ui["listColor"])),
            "BackgroundTransparency": 1.0,
            "BorderSizePixel": 0,
            "ClipsDescendants": True,
            "Visible": True,
            "ZIndex": 2,
            "AutomaticCanvasSize": 2,
            "CanvasSize": ("UDim2", (0, 0, 0, 0)),
            "ScrollingDirection": 2,
            "ScrollingEnabled": True,
            "ScrollBarThickness": int(ui.get("scrollBarThickness", 11)),
            "ScrollBarImageColor3": ("Color3", tuple(accent)),
            "ScrollBarImageTransparency": 0.0,
            "VerticalScrollBarInset": 1,
            "Active": True,
            "Selectable": True,
            "LayoutOrder": 0,
        }

        close_props = {
            "AnchorPoint": ("Vector2", (1, 0)),
            "Position": ("UDim2", (1, -8, 0, 8)),
            "Size": ("UDim2", (0, 34, 0, 34)),
            "BackgroundColor3": ("Color3", tuple(ui["closeColor"])),
            "BackgroundTransparency": 0.0,
            "BorderSizePixel": 0,
            "Visible": True,
            "ZIndex": 5,
            "AutoButtonColor": True,
            "LayoutOrder": 0,
        }
        close_props.update(text_overrides("X", size=20, scaled=True, x_align=2,
                                          color=(255, 255, 255), font=F["main"]))

        children = (
            ui_corner(b, ui.get("panelCorner", 0.025), scale=True, depth=D + 1)
            + ui_stroke(b, stroke, ui.get("panelStrokeWidth", 4.5), 0, depth=D + 1)
            # Shipped panels keep their shape on any screen with an aspect
            # constraint; at the design size it is a no-op (fw / fh), and on a
            # narrow screen it stops the panel squashing its rows.
            + ui_aspect(b, round(float(fw) / float(fh), 6), depth=D + 1)
            + b.item("TextLabel", "Title", title_props,
                     children=(ui_stroke(b, stroke, ui.get("titleStrokeWidth", 3), 0, depth=D + 2)
                               + text_size(b, 40, 12, depth=D + 2)),
                     depth=D + 1)[0]
        )

        if has_status:
            # A claim-all button shares this line, so the status text gives way.
            status_props = {
                "Position": ("UDim2", (0.03, 0, 0.1, 0)),
                "Size": ("UDim2", (0.6 if has_claim_all else 0.94, 0, 0.08, 0)),
                "BackgroundTransparency": 1.0,
                "BorderSizePixel": 0,
                "Visible": True,
                "ZIndex": 3,
                "LayoutOrder": 0,
            }
            status_props.update(text_overrides("", size=18, scaled=True,
                                               x_align=0 if has_claim_all else 2,
                                               color=tuple(ui["subText"]), font=F["alt"]))
            children += b.item("TextLabel", "Status", status_props,
                               children=(ui_stroke(b, stroke, 3, 0, depth=D + 2)
                                         + text_size(b, 26, 10, depth=D + 2)),
                               depth=D + 1)[0]

        if has_claim_all:
            claim_props = {
                "Position": ("UDim2", (0.66, 0, 0.095, 0)),
                "Size": ("UDim2", (0.31, 0, 0.085, 0)),
                "BackgroundColor3": ("Color3", tuple(ui["actionColor"])),
                "BackgroundTransparency": 0.0,
                "BorderSizePixel": 0,
                "Visible": True,
                "ZIndex": 4,
                "AutoButtonColor": True,
                "LayoutOrder": 0,
            }
            claim_props.update(text_overrides("Claim All", size=16, scaled=True, x_align=2,
                                              color=(255, 255, 255), font=F["main"]))
            children += b.item("TextButton", "ClaimAll", claim_props,
                               children=(ui_corner(b, 8, depth=D + 2)
                                         + ui_stroke(b, stroke, 3, 0, depth=D + 2)
                                         + text_size(b, 22, 9, depth=D + 2)),
                               depth=D + 1)[0]

        if has_bar:
            bar_props = {
                "Position": ("UDim2", (0.03, 0, 0.1, 0)),
                "Size": ("UDim2", (0.94, 0, 0.085, 0)),
                "BackgroundColor3": ("Color3", tuple(ui["inputColor"])),
                "BackgroundTransparency": 0.0,
                "BorderSizePixel": 0,
                "Visible": True,
                "ZIndex": 5,
                "LayoutOrder": 0,
                "ClipsDescendants": False,
            }
            box_props = {
                "BackgroundTransparency": 1.0,
                "BorderSizePixel": 0,
                "Position": ("UDim2", (0, 12, 0, 0)),
                "Size": ("UDim2", (1, -112, 1, 0)),
                "Visible": True,
                "ZIndex": 6,
                "ClearTextOnFocus": False,
                "PlaceholderText": "type a command, then Enter",
                "PlaceholderColor3": ("Color3", (90, 90, 90)),
                "TextEditable": True,
                "LayoutOrder": 0,
            }
            box_props.update(text_overrides("", size=15, scaled=True, x_align=0,
                                            color=tuple(ui["inputText"]), font=F["main"]))
            send_props = {
                "Position": ("UDim2", (1, -92, 0.1, 0)),
                "Size": ("UDim2", (0, 82, 0.8, 0)),
                "BackgroundColor3": ("Color3", tuple(ui["actionColor"])),
                "BackgroundTransparency": 0.0,
                "BorderSizePixel": 0,
                "Visible": True,
                "ZIndex": 6,
                "AutoButtonColor": True,
                "LayoutOrder": 0,
            }
            send_props.update(text_overrides("Run", size=15, scaled=True, x_align=2,
                                             color=(255, 255, 255), font=F["main"]))
            children += b.item("Frame", "CommandBar", bar_props,
                               children=(ui_corner(b, 8, depth=D + 2)
                                         + ui_stroke(b, stroke, 3, 0, depth=D + 2)
                                         + b.item("TextBox", "Input", box_props,
                                                  children=text_size(b, 22, 9, depth=D + 3),
                                                  depth=D + 2)[0]
                                         + b.item("TextButton", "Send", send_props,
                                                  children=(ui_corner(b, 8, depth=D + 3)
                                                            + ui_stroke(b, stroke, 2.5, 0, depth=D + 3)
                                                            + text_size(b, 20, 9, depth=D + 3)),
                                                  depth=D + 2)[0]),
                               depth=D + 1)[0]

        children += b.item("ScrollingFrame", "List", list_props,
                           children=(ui_padding(b, 0, 0, 4, 4, depth=D + 2)
                                     + ui_list_layout(b, 8, 2, 1, 0, depth=D + 2)
                                     + row_template(b, ui, D + 2)
                                     + section_template(b, ui, D + 2)),
                           depth=D + 1)[0]

        children += b.item("TextButton", "Close", close_props,
                           children=(ui_corner(b, 8, depth=D + 2)
                                     + ui_stroke(b, stroke, 3, 0, depth=D + 2)
                                     + text_size(b, 24, 10, depth=D + 2)),
                           depth=D + 1)[0]

        out.append(b.item("Frame", name, frame_props, children=children, depth=D)[0])
    return "".join(out)


# ---------------------------------------------------------------------------
# kill feed and zone warning (StarterGui)
# ---------------------------------------------------------------------------

def killfeed(b, gd):
    """StarterGui/KillFeed: strip under the menu row that reports who ate whom.

    Purple like the rest of the game's chrome, black outline, FredokaOne text -
    the shipped HUD's own vocabulary rather than a new one.
    """
    ui = gd["ui"]
    F = fonts(ui)
    spec = ui.get("killFeed") or {}
    stroke = ui.get("panelStroke", [0, 0, 0])

    entry_props = {
        "BackgroundColor3": ("Color3", tuple(spec.get("color", [170, 85, 255]))),
        "BackgroundTransparency": float(spec.get("transparency", 0.15)),
        "BorderSizePixel": 0,
        "Size": ("UDim2", (1, 0, 0, int(spec.get("entryHeight", 28)))),
        "Visible": False,          # template
        "ZIndex": 2,
        "LayoutOrder": 0,
        "ClipsDescendants": False,
    }
    entry_props.update(text_overrides("", size=15, scaled=True, x_align=0,
                                      color=tuple(spec.get("text", [255, 255, 255])),
                                      font=F["alt"]))

    entries_props = {
        "AnchorPoint": ("Vector2", (0.5, 0)),
        "BackgroundColor3": ("Color3", (0, 0, 0)),
        "BackgroundTransparency": 1.0,
        "BorderSizePixel": 0,
        "Position": ("UDim2", (0.5, 0, float(spec.get("y", 0.17)), 0)),
        "Size": ("UDim2", (0, int(spec.get("width", 430)), 0, int(spec.get("height", 168)))),
        "Visible": True,
        "ZIndex": 1,
        "ClipsDescendants": False,
        "LayoutOrder": 0,
    }

    entries = b.item("Frame", "Entries", entries_props,
                     children=(ui_list_layout(b, 5, 2, 1, 0, depth=D + 2)
                               + b.item("TextLabel", "Entry", entry_props,
                                        children=(ui_corner(b, 8, depth=D + 3)
                                                  + ui_stroke(b, stroke, 3, 0, depth=D + 3)
                                                  + ui_padding(b, 12, 12, 0, 0, depth=D + 3)
                                                  + text_size(b, 20, 9, depth=D + 3)),
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
    stops the gate feeling arbitrary. Gold FredokaOne text with a black outline,
    which is how the shipped UI writes warnings.
    """
    ui = gd["ui"]
    F = fonts(ui)
    spec = ui.get("zoneWarn") or {}
    stroke = ui.get("panelStroke", [0, 0, 0])

    label_props = {
        "AnchorPoint": ("Vector2", (0.5, 0)),
        "BackgroundTransparency": 1.0,
        "BorderSizePixel": 0,
        "Position": ("UDim2", (0.5, 0, float(spec.get("y", 0.34)), 0)),
        "Size": ("UDim2", (0, int(spec.get("width", 470)), 0, int(spec.get("height", 46)))),
        "Visible": True,
        "ZIndex": 3,
        "LayoutOrder": 0,
        "ClipsDescendants": False,
    }
    label_props.update(text_overrides("", size=19, scaled=True, x_align=2,
                                      color=tuple(spec.get("text", [249, 173, 0])),
                                      font=F["alt"]))

    tint_props = {
        "BackgroundColor3": ("Color3", (0, 0, 0)),
        "BackgroundTransparency": 1.0,
        "BorderSizePixel": 0,
        "Position": ("UDim2", (0, 0, 0, 0)),
        "Size": ("UDim2", (1, 0, 1, 0)),
        "Visible": False,
        "ZIndex": 2,
        "ClipsDescendants": False,
        "LayoutOrder": 0,
    }

    tint = b.item("Frame", "Tint", tint_props,
                  children=(b.item("UIStroke", "UIStroke", {
                                      "ApplyStrokeMode": 0,     # Border
                                      "Color": ("Color3", tuple(spec.get("edge", [235, 70, 70]))),
                                      "Thickness": 16.0,
                                      "Transparency": 0.35,
                                      "Enabled": True,
                                      "LineJoinMode": 2,
                                  }, depth=D + 2)[0]
                            + b.item("TextLabel", "Label", label_props,
                                     children=(ui_stroke(b, stroke, 4, 0, depth=D + 3)
                                               + text_size(b, 26, 10, depth=D + 3)),
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
    """Toast stack. White card, black outline, kind colour as the accent stroke -
    the same recipe as the shipped panels, so a toast reads as part of the game."""
    ui = gd["ui"]
    F = fonts(ui)
    kinds = gd["notifier"]["kinds"]
    stroke = ui.get("panelStroke", [0, 0, 0])

    toast_props = {
        "Size": ("UDim2", (1, 0, 0, 36)),
        "BackgroundColor3": ("Color3", tuple(ui["panelColor"])),
        "BackgroundTransparency": 0.05,
        "BorderSizePixel": 0,
        "Visible": False,
        "ZIndex": 6,
        "LayoutOrder": 0,
        "ClipsDescendants": False,
    }
    toast_props.update(text_overrides("", size=16, scaled=True, x_align=2, wrapped=True,
                                      color=tuple(ui.get("inputText", [60, 60, 60])),
                                      font=F["main"]))

    container_props = {
        "AnchorPoint": ("Vector2", (0.5, 1)),
        "Position": ("UDim2", (0.5, 0, 0.72, 0)),
        "Size": ("UDim2", (0, 420, 0, 220)),
        "BackgroundColor3": ("Color3", (255, 255, 255)),
        "BackgroundTransparency": 1.0,
        "BorderSizePixel": 0,
        "Visible": True,
        "ZIndex": 5,
        "ClipsDescendants": False,
        "LayoutOrder": 0,
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
                           + ui_stroke(b, kinds["info"], 3, 0, depth=D + 3)
                           + ui_padding(b, 14, 14, 0, 0, depth=D + 3)
                           + text_size(b, 22, 10, depth=D + 3)),
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
# zones (Workspace/Zones) - every zone is its own arena
# ---------------------------------------------------------------------------

# Copied off the shipped hub arena so a zone arena is built the same way instead
# of invented: a 16 stud floor slab whose top face sits at FloorY, textured with
# rbxassetid://6372755229 tiled every 8 studs, and walls 4 studs thick, 87 tall,
# 40% see through, wearing rbxassetid://6794250394 tiled every 9 studs on all six
# faces. Only the colour changes: floor in the zone colour, walls the same colour
# pulled dark, so an arena reads as one place from far away.
FLOOR_TEXTURE = "rbxassetid://6372755229"
FLOOR_TILE = 8
WALL_TEXTURE = "rbxassetid://6794250394"
WALL_TILE = 9
WALL_TRANSPARENCY = 0.4
PLASTIC = 256       # Enum.Material.Plastic, what every shipped map part uses
SMOOTH = 0          # Enum.SurfaceType.Smooth
PERSISTENT = 2      # Enum.ModelStreamingMode.Persistent: never streamed out


def zone_req_text(zone):
    if zone.get("reqRebirth"):
        n = zone["reqRebirth"]
        return "Requires %d Rebirth%s" % (n, "" if n == 1 else "s")
    if zone.get("reqSize"):
        return "Requires Size %d" % zone["reqSize"]
    return "Unlocked"


def darken(rgb, factor=0.42):
    """The zone colour pulled dark for walls: still names the arena, but dark
    enough to sit behind the shipped wall texture the way the hub's blue does."""
    return tuple(max(0, min(255, int(round(c * factor)))) for c in rgb)


def map_part(rgb, center, size, transparency=0.0):
    """Properties shared by every generated map part (floor slabs and walls)."""
    return {
        "shape": 1,          # Enum.PartType.Block
        "Anchored": True,
        "CanCollide": True,
        "CanQuery": True,
        "CanTouch": False,
        "CastShadow": False,
        "Locked": False,
        "Transparency": float(transparency),
        "Reflectance": 0.0,
        "Material": PLASTIC,
        "Color3uint8": ("Color3uint8", tuple(rgb)),
        "TopSurface": SMOOTH,
        "BottomSurface": SMOOTH,
        "CFrame": ("CoordinateFrame", tuple(center)),
        "size": ("Vector3", tuple(size)),
    }


def wall_faces(b, depth):
    """The shipped wall texture on all six faces, tiled by studs so a wall of any
    length keeps the same brick size instead of stretching it."""
    return "".join(b.item("Texture", "Texture", {
        "Face": face,
        "Texture": ("Content", "<url>%s</url>" % WALL_TEXTURE),
        "StudsPerTileU": float(WALL_TILE),
        "StudsPerTileV": float(WALL_TILE),
        "Color3": ("Color3", (255, 255, 255)),
        "Transparency": 0.9,
        "ZIndex": 1,
    }, depth=depth)[0] for face in (0, 1, 2, 3, 4, 5))


def zone_wall(b, name, size, center, rgb, depth=D + 2):
    return b.item("Part", name, map_part(rgb, center, size, WALL_TRANSPARENCY),
                  children=wall_faces(b, depth + 1), depth=depth)[0]


def zone_sign(b, zone, offset_y, depth=D + 3):
    """Billboard floating over the arena: name, rarity and requirement, in the
    HUD's own face and colours, so the map and the Zones menu say one thing."""
    label = {
        "Size": ("UDim2", (1, 0, 1, 0)),
        "BackgroundColor3": ("Color3", tuple(zone["color"])),
        "BackgroundTransparency": 0.0,
        "BorderSizePixel": 0,
        "Visible": True,
        "ZIndex": 2,
    }
    label.update(text_overrides(
        "%s\n%s cubes  |  %s" % (zone["name"], zone["rarity"], zone_req_text(zone)),
        size=26, scaled=True, x_align=1, wrapped=True, font=("raw", FONT_ALT)))
    return b.item("BillboardGui", "Sign", {
        "AlwaysOnTop": False,
        "Enabled": True,
        "ClipsDescendants": False,
        "StudsOffset": ("Vector3", (0, offset_y, 0)),
        "LightInfluence": 0.0,
        "Size": ("UDim2", (0, 340, 0, 100)),
        "MaxDistance": 1400.0,
        "ResetOnSpawn": False,
        "ZIndexBehavior": 1,
    }, children=b.item("TextLabel", "Label", label,
                       children=(ui_corner(b, 14, depth=depth + 2)
                                 + ui_stroke(b, (0, 0, 0), 4, 0, depth=depth + 2)
                                 + text_size(b, 34, 14, depth=depth + 2)),
                       depth=depth + 1)[0],
        depth=depth)[0]


def zone_floor(b, size, center, rgb, sign, depth=D + 2):
    """The walking surface. It IS the zone region: Food spawns inside its bounds
    and Progression teleports to its centre, so resizing it in Studio resizes the
    zone. The sign rides along because a billboard adornees the part it is in."""
    texture = b.item("Texture", "Texture", {
        "Face": 1,           # the top face, exactly as the shipped Baseplates have it
        "Texture": ("Content", "<url>%s</url>" % FLOOR_TEXTURE),
        "StudsPerTileU": float(FLOOR_TILE),
        "StudsPerTileV": float(FLOOR_TILE),
        "Color3": ("Color3", (0, 0, 0)),
        "Transparency": 0.8,
        "ZIndex": 1,
    }, depth=depth + 1)[0]
    return b.item("Part", "Floor", map_part(rgb, center, size),
                  children=texture + sign, depth=depth)[0]


def zones(b, gd):
    """Workspace/Zones: one arena per zone, not one pad inside the hub arena.

    Each zone is a Model holding its floor slab, four walls, a sign and the
    zone's own Id/Rarity/ReqSize/ReqRebirth/Color values, so it can be picked up
    and moved as a single thing in Studio - and so the game keeps reading the map
    instead of a config: Food spawns inside the floor, Progression teleports to
    its centre, and the client draws the Zones menu from the same instances.

    The models are Persistent (never streamed out) on purpose. The client reads
    zone names, colours and requirements off them, and that menu has to list all
    five arenas while the player stands in the hub, 1500 studs from the nearest
    one; twenty-five parts is a cheap price for that.
    """
    settings = gd["settings"]
    floor_y = float(settings["FloorY"])
    slab = float(settings["ZoneFloorThickness"])
    wall_h = float(settings["ZoneWallHeight"])
    wall_t = float(settings["ZoneWallThickness"])
    out = []
    for z in gd["zones"]:
        cx, cz = float(z["center"][0]), float(z["center"][1])
        r = float(z["radius"])
        rgb = tuple(z["color"])
        shade = darken(rgb)
        wall_y = floor_y + wall_h / 2.0
        span = 2 * r

        # Walls stand just outside the floor edge, so the whole slab is playable
        # and the east/west walls are the long ones (they close the corners).
        floor = zone_floor(b, (span, slab, span), (cx, floor_y - slab / 2.0, cz), rgb,
                           zone_sign(b, z, wall_h + slab / 2.0 + 30.0), D + 2)
        walls = (
            zone_wall(b, "WallEast", (wall_t, wall_h, span + 2 * wall_t),
                      (cx + r + wall_t / 2.0, wall_y, cz), shade)
            + zone_wall(b, "WallWest", (wall_t, wall_h, span + 2 * wall_t),
                        (cx - r - wall_t / 2.0, wall_y, cz), shade)
            + zone_wall(b, "WallNorth", (span, wall_h, wall_t),
                        (cx, wall_y, cz + r + wall_t / 2.0), shade)
            + zone_wall(b, "WallSouth", (span, wall_h, wall_t),
                        (cx, wall_y, cz - r - wall_t / 2.0), shade)
        )
        values = (integer(b, "Id", z["id"], D + 2)
                  + string(b, "Rarity", z["rarity"], D + 2)
                  + num(b, "ReqSize", z.get("reqSize", 0), D + 2)
                  + num(b, "ReqRebirth", z.get("reqRebirth", 0), D + 2)
                  + color(b, "Color", rgb, D + 2))
        out.append(b.bare_item("Model", z["name"],
                               [("token", "ModelStreamingMode", PERSISTENT)],
                               children=floor + walls + values, depth=D + 1)[0])

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
        "StarterGui/Buttons": tab_buttons(b, gd),
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
