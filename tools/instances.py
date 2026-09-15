#!/usr/bin/env python3
"""Generate the new non-script instances (RemoteEvents, menu buttons, frames,
zone platforms) for build_together.py. Returns a list of (parent_ref, xml)."""
import re, json, os, random

random.seed(1234)

def sanitize(t):
    return t.replace(chr(0), "").replace("&#0;", "").replace("&#x0;", "")

def gen_uid(existing):
    while True:
        h = "".join(random.choice("0123456789abcdef") for _ in range(32))
        ref = "RBX" + h
        if ref not in existing:
            existing.add(ref)
            return ref

def common(name, ref):
    return (
        '\t\t\t\t\t<SecurityCapabilities name="Capabilities">0</SecurityCapabilities>\n'
        '\t\t\t\t\t<bool name="DefinesCapabilities">false</bool>\n'
        '\t\t\t\t\t<UniqueId name="HistoryId">00000000000000000000000000000000</UniqueId>\n'
        '\t\t\t\t\t<string name="Name">' + name + '</string>\n'
        '\t\t\t\t\t<int64 name="SourceAssetId">-1</int64>\n'
        '\t\t\t\t\t<SharedString name="Tags"></SharedString>\n'
        '\t\t\t\t\t<UniqueId name="UniqueId">' + ref + '</UniqueId>\n'
    )

def gen_event(name, existing):
    ref = gen_uid(existing)
    xml = (
        '\t\t\t<Item class="RemoteEvent" referent="' + ref + '">\n'
        '\t\t\t\t<Properties>\n'
        '\t\t\t\t\t<BinaryString name="AttributesSerialize"></BinaryString>\n'
        '\t\t\t\t\t<SecurityCapabilities name="Capabilities">0</SecurityCapabilities>\n'
        '\t\t\t\t\t<bool name="DefinesCapabilities">false</bool>\n'
        '\t\t\t\t\t<UniqueId name="HistoryId">00000000000000000000000000000000</UniqueId>\n'
        '\t\t\t\t\t<string name="Name">' + name + '</string>\n'
        '\t\t\t\t\t<int64 name="SourceAssetId">-1</int64>\n'
        '\t\t\t\t\t<SharedString name="Tags"></SharedString>\n'
        '\t\t\t\t\t<UniqueId name="UniqueId">' + ref + '</UniqueId>\n'
        '\t\t\t\t</Properties>\n'
        '\t\t\t</Item>\n'
    )
    return xml, ref

def gen_button(name, existing, xs, ys):
    ref = gen_uid(existing)
    xml = (
        '\t\t\t<Item class="TextButton" referent="' + ref + '">\n'
        '\t\t\t\t<Properties>\n'
        '\t\t\t\t\t<bool name="Active">true</bool>\n'
        '\t\t\t\t\t<Vector2 name="AnchorPoint"><X>0</X><Y>0</Y></Vector2>\n'
        '\t\t\t\t\t<token name="AutomaticSize">0</token>\n'
        '\t\t\t\t\t<Color3 name="BackgroundColor3"><R>1</R><G>0.85</G><B>0.1</B></Color3>\n'
        '\t\t\t\t\t<float name="BackgroundTransparency">0</float>\n'
        '\t\t\t\t\t<Color3 name="BorderColor3"><R>0</R><G>0</G><B>0</B></Color3>\n'
        '\t\t\t\t\t<token name="BorderMode">0</token>\n'
        '\t\t\t\t\t<int name="BorderSizePixel">0</int>\n'
        '\t\t\t\t\t<bool name="ClipsDescendants">false</bool>\n'
        '\t\t\t\t\t<bool name="Draggable">false</bool>\n'
        '\t\t\t\t\t<bool name="Interactable">true</bool>\n'
        '\t\t\t\t\t<int name="LayoutOrder">0</int>\n'
        '\t\t\t\t\t<Font name="FontFace"><Family><url>rbxassetid://12187365977</url></Family><Weight>700</Weight><Style>Normal</Style></Font>\n'
        '\t\t\t\t\t<bool name="RichText">false</bool>\n'
        '\t\t\t\t\t<Color3 name="TextColor3"><R>0</R><G>0</G><B>0</B></Color3>\n'
        '\t\t\t\t\t<token name="TextDirection">0</token>\n'
        '\t\t\t\t\t<bool name="TextScaled">true</bool>\n'
        '\t\t\t\t\t<float name="TextSize">16</float>\n'
        '\t\t\t\t\t<float name="TextStrokeTransparency">1</float>\n'
        '\t\t\t\t\t<token name="TextTruncate">0</token>\n'
        '\t\t\t\t\t<bool name="TextWrapped">true</bool>\n'
        '\t\t\t\t\t<token name="TextXAlignment">2</token>\n'
        '\t\t\t\t\t<token name="TextYAlignment">1</token>\n'
        '\t\t\t\t\t<UDim2 name="Position"><XS>' + xs + '</XS><XO>0</XO><YS>' + ys + '</YS><YO>0</YO></UDim2>\n'
        '\t\t\t\t\t<UDim2 name="Size"><XS>0.085</XS><XO>0</XO><YS>0.1</YS><YO>0</YO></UDim2>\n'
        '\t\t\t\t\t<token name="SizeConstraint">0</token>\n'
        '\t\t\t\t\t<bool name="Visible">true</bool>\n'
        '\t\t\t\t\t<int name="ZIndex">2</int>\n'
        + common(name, ref) +
        '\t\t\t\t</Properties>\n'
        '\t\t\t</Item>\n'
    )
    return xml, ref

def gen_frame(name, existing, src):
    src = sanitize(src)
    ref = gen_uid(existing)
    title_ref = gen_uid(existing)
    list_ref = gen_uid(existing)
    listlay_ref = gen_uid(existing)
    uic_ref = gen_uid(existing)
    ls_ref = gen_uid(existing)
    src_cdata = src.replace("]]>", "]] >")
    inner = (
        '\t\t\t\t<Item class="UICorner" referent="' + uic_ref + '">\n'
        '\t\t\t\t\t<Properties>\n'
        '\t\t\t\t\t\t<int name="CornerRadius">14</int>\n'
        + common("UICorner", uic_ref) +
        '\t\t\t\t\t</Properties>\n'
        '\t\t\t\t</Item>\n'
        '\t\t\t\t<Item class="TextLabel" referent="' + title_ref + '">\n'
        '\t\t\t\t\t<Properties>\n'
        '\t\t\t\t\t\t<Font name="FontFace"><Family><url>rbxassetid://12187365977</url></Family><Weight>700</Weight><Style>Normal</Style></Font>\n'
        '\t\t\t\t\t\t<bool name="RichText">false</bool>\n'
        '\t\t\t\t\t\t<string name="Text">' + name + '</string>\n'
        '\t\t\t\t\t\t<Color3 name="TextColor3"><R>1</R><G>1</G><B>1</B></Color3>\n'
        '\t\t\t\t\t\t<bool name="TextScaled">true</bool>\n'
        '\t\t\t\t\t\t<float name="TextSize">26</float>\n'
        '\t\t\t\t\t\t<float name="TextTransparency">0</float>\n'
        '\t\t\t\t\t\t<token name="TextTruncate">0</token>\n'
        '\t\t\t\t\t\t<bool name="TextWrapped">true</bool>\n'
        '\t\t\t\t\t\t<token name="TextXAlignment">2</token>\n'
        '\t\t\t\t\t\t<token name="TextYAlignment">1</token>\n'
        '\t\t\t\t\t\t<Color3 name="BackgroundColor3"><R>0.15</R><G>0.15</G><B>0.25</B></Color3>\n'
        '\t\t\t\t\t\t<float name="BackgroundTransparency">0.2</float>\n'
        '\t\t\t\t\t\t<UDim2 name="Position"><XS>0</XS><XO>0</XO><YS>0</YS><YO>0</YO></UDim2>\n'
        '\t\t\t\t\t\t<UDim2 name="Size"><XS>1</XS><XO>0</XO><YS>0.12</YS><YO>0</YO></UDim2>\n'
        '\t\t\t\t\t\t<bool name="Visible">true</bool>\n'
        '\t\t\t\t\t\t<int name="ZIndex">2</int>\n'
        + common("Title", title_ref) +
        '\t\t\t\t\t</Properties>\n'
        '\t\t\t\t</Item>\n'
        '\t\t\t\t<Item class="ScrollingFrame" referent="' + list_ref + '">\n'
        '\t\t\t\t\t<Properties>\n'
        '\t\t\t\t\t\t<Color3 name="BackgroundColor3"><R>0.12</R><G>0.12</G><B>0.18</B></Color3>\n'
        '\t\t\t\t\t\t<float name="BackgroundTransparency">0.1</float>\n'
        '\t\t\t\t\t\t<int name="BorderSizePixel">0</int>\n'
        '\t\t\t\t\t\t<token name="ScrollingDirection">1</token>\n'
        '\t\t\t\t\t\t<token name="VerticalScrollBarInset">1</token>\n'
        '\t\t\t\t\t\t<int name="ScrollBarThickness">8</int>\n'
        '\t\t\t\t\t\t<UDim2 name="CanvasSize"><XS>0</XS><XO>0</XO><YS>0</YS><YO>0</YO></UDim2>\n'
        '\t\t\t\t\t\t<UDim2 name="Position"><XS>0.03</XS><XO>0</XO><YS>0.14</YS><YO>0</YO></UDim2>\n'
        '\t\t\t\t\t\t<UDim2 name="Size"><XS>0.94</XS><XO>0</XO><YS>0.82</YS><YO>0</YO></UDim2>\n'
        '\t\t\t\t\t\t<bool name="Visible">true</bool>\n'
        '\t\t\t\t\t\t<int name="ZIndex">2</int>\n'
        + common("List", list_ref) +
        '\t\t\t\t\t</Properties>\n'
        '\t\t\t\t\t<Item class="UIListLayout" referent="' + listlay_ref + '">\n'
        '\t\t\t\t\t\t<Properties>\n'
        '\t\t\t\t\t\t\t<token name="SortOrder">0</token>\n'
        '\t\t\t\t\t\t\t<token name="HorizontalAlignment">0</token>\n'
        '\t\t\t\t\t\t\t<token name="VerticalAlignment">0</token>\n'
        '\t\t\t\t\t\t\t<UDim2 name="Padding"><XS>0</XS><XO>0</XO><YS>0</YS><YO>6</YO></UDim2>\n'
        + common("UIListLayout", listlay_ref) +
        '\t\t\t\t\t\t</Properties>\n'
        '\t\t\t\t\t</Item>\n'
        '\t\t\t\t</Item>\n'
        '\t\t\t\t<Item class="LocalScript" referent="' + ls_ref + '">\n'
        '\t\t\t\t\t<Properties>\n'
        '\t\t\t\t\t\t<ProtectedString name="Source"><![CDATA[' + src_cdata + ']]></ProtectedString>\n'
        '\t\t\t\t\t\t<bool name="Disabled">false</bool>\n'
        '\t\t\t\t\t\t<Content name="LinkedSource"><null></null></Content>\n'
        '\t\t\t\t\t\t<token name="RunContext">0</token>\n'
        '\t\t\t\t\t\t<string name="ScriptGuid">{85b1a1c1-0000-4000-8000-000000000001}</string>\n'
        '\t\t\t\t\t\t<BinaryString name="AttributesSerialize"></BinaryString>\n'
        '\t\t\t\t\t\t<SecurityCapabilities name="Capabilities">0</SecurityCapabilities>\n'
        '\t\t\t\t\t\t<bool name="DefinesCapabilities">false</bool>\n'
        '\t\t\t\t\t\t<UniqueId name="HistoryId">00000000000000000000000000000000</UniqueId>\n'
        '\t\t\t\t\t\t<string name="Name">FrameScript</string>\n'
        '\t\t\t\t\t\t<int64 name="SourceAssetId">-1</int64>\n'
        '\t\t\t\t\t\t<SharedString name="Tags"></SharedString>\n'
        '\t\t\t\t\t\t<UniqueId name="UniqueId">' + ls_ref + '</UniqueId>\n'
        '\t\t\t\t\t</Properties>\n'
        '\t\t\t\t</Item>\n'
    )
    frame_xml = (
        '\t\t\t<Item class="Frame" referent="' + ref + '">\n'
        '\t\t\t\t<Properties>\n'
        '\t\t\t\t\t<token name="Style">0</token>\n'
        '\t\t\t\t\t<bool name="Active">false</bool>\n'
        '\t\t\t\t\t<Vector2 name="AnchorPoint"><X>0.5</X><Y>0.5</Y></Vector2>\n'
        '\t\t\t\t\t<token name="AutomaticSize">0</token>\n'
        '\t\t\t\t\t<Color3 name="BackgroundColor3"><R>1</R><G>1</G><B>1</B></Color3>\n'
        '\t\t\t\t\t<float name="BackgroundTransparency">0</float>\n'
        '\t\t\t\t\t<Color3 name="BorderColor3"><R>0</R><G>0</G><B>0</B></Color3>\n'
        '\t\t\t\t\t<token name="BorderMode">0</token>\n'
        '\t\t\t\t\t<int name="BorderSizePixel">0</int>\n'
        '\t\t\t\t\t<bool name="ClipsDescendants">false</bool>\n'
        '\t\t\t\t\t<bool name="Draggable">false</bool>\n'
        '\t\t\t\t\t<bool name="Interactable">true</bool>\n'
        '\t\t\t\t\t<int name="LayoutOrder">0</int>\n'
        '\t\t\t\t\t<Ref name="NextSelectionDown">null</Ref>\n'
        '\t\t\t\t\t<Ref name="NextSelectionLeft">null</Ref>\n'
        '\t\t\t\t\t<Ref name="NextSelectionRight">null</Ref>\n'
        '\t\t\t\t\t<Ref name="NextSelectionUp">null</Ref>\n'
        '\t\t\t\t\t<UDim2 name="Position"><XS>0.5</XS><XO>0</XO><YS>0.5</YS><YO>0</YO></UDim2>\n'
        '\t\t\t\t\t<float name="Rotation">0</float>\n'
        '\t\t\t\t\t<bool name="Selectable">false</bool>\n'
        '\t\t\t\t\t<Ref name="SelectionImageObject">null</Ref>\n'
        '\t\t\t\t\t<int name="SelectionOrder">0</int>\n'
        '\t\t\t\t\t<token name="Sink">0</token>\n'
        '\t\t\t\t\t<UDim2 name="Size"><XS>0.5</XS><XO>0</XO><YS>0.6</YS><YO>0</YO></UDim2>\n'
        '\t\t\t\t\t<token name="SizeConstraint">0</token>\n'
        '\t\t\t\t\t<bool name="Visible">false</bool>\n'
        '\t\t\t\t\t<int name="ZIndex">1</int>\n'
        + common(name, ref) +
        '\t\t\t\t</Properties>\n'
        + inner +
        '\t\t\t</Item>\n'
    )
    return frame_xml, ref

def gen_zone_platform(zone, existing):
    ref = gen_uid(existing)
    sign_ref = gen_uid(existing)
    lbl_ref = gen_uid(existing)
    cx, cy, cz = zone["center"]
    r = zone["radius"]
    col = zone["color"]
    coloruint = (col[0] << 16) | (col[1] << 8) | col[2]
    part = (
        '\t\t\t<Item class="Part" referent="' + ref + '">\n'
        '\t\t\t\t<Properties>\n'
        '\t\t\t\t\t<bool name="Anchored">true</bool>\n'
        '\t\t\t\t\t<bool name="AudioCanCollide">true</bool>\n'
        '\t\t\t\t\t<token name="BackSurface">0</token>\n'
        '\t\t\t\t\t<token name="BottomSurface">0</token>\n'
        '\t\t\t\t\t<CoordinateFrame name="CFrame"><X>' + str(cx) + '</X><Y>1</Y><Z>' + str(cz) + '</Z><R00>1</R00><R01>0</R01><R02>0</R02><R10>0</R10><R11>1</R11><R12>0</R12><R20>0</R20><R21>0</R21><R22>1</R22></CoordinateFrame>\n'
        '\t\t\t\t\t<bool name="CanCollide">true</bool>\n'
        '\t\t\t\t\t<bool name="CanQuery">true</bool>\n'
        '\t\t\t\t\t<bool name="CanTouch">false</bool>\n'
        '\t\t\t\t\t<bool name="CastShadow">true</bool>\n'
        '\t\t\t\t\t<string name="CollisionGroup">Default</string>\n'
        '\t\t\t\t\t<int name="CollisionGroupId">0</int>\n'
        '\t\t\t\t\t<Color3uint8 name="Color3uint8">' + str(coloruint) + '</Color3uint8>\n'
        '\t\t\t\t\t<bool name="EnableFluidForces">true</bool>\n'
        '\t\t\t\t\t<token name="Material">288</token>\n'
        '\t\t\t\t\t<CoordinateFrame name="PivotOffset"><X>0</X><Y>0</Y><Z>0</Z><R00>1</R00><R01>0</R01><R02>0</R02><R10>0</R10><R11>1</R11><R12>0</R12><R20>0</R20><R21>0</R21><R22>1</R22></CoordinateFrame>\n'
        '\t\t\t\t\t<float name="Reflectance">0</float>\n'
        '\t\t\t\t\t<token name="Shape">1</token>\n'
        '\t\t\t\t\t<float name="Transparency">0</float>\n'
        '\t\t\t\t\t<Vector3 name="size"><X>' + str(r*2) + '</X><Y>1</Y><Z>' + str(r*2) + '</Z></Vector3>\n'
        '\t\t\t\t\t<BinaryString name="AttributesSerialize"></BinaryString>\n'
        '\t\t\t\t\t<SecurityCapabilities name="Capabilities">0</SecurityCapabilities>\n'
        '\t\t\t\t\t<bool name="DefinesCapabilities">false</bool>\n'
        '\t\t\t\t\t<UniqueId name="HistoryId">00000000000000000000000000000000</UniqueId>\n'
        '\t\t\t\t\t<string name="Name">' + zone["name"] + '</string>\n'
        '\t\t\t\t\t<int64 name="SourceAssetId">-1</int64>\n'
        '\t\t\t\t\t<SharedString name="Tags"></SharedString>\n'
        '\t\t\t\t\t<UniqueId name="UniqueId">' + ref + '</UniqueId>\n'
        '\t\t\t\t</Properties>\n'
        '\t\t\t\t<Item class="BillboardGui" referent="' + sign_ref + '">\n'
        '\t\t\t\t\t<Properties>\n'
        '\t\t\t\t\t\t<bool name="AlwaysOnTop">false</bool>\n'
        '\t\t\t\t\t\t<bool name="Enabled">true</bool>\n'
        '\t\t\t\t\t\t<bool name="ClipsDescendants">false</bool>\n'
        '\t\t\t\t\t\t<Vector3 name="StudsOffset"><X>0</X><Y>4</Y><Z>0</Z></Vector3>\n'
        '\t\t\t\t\t\t<UDim2 name="Size"><XS>0</XS><XO>220</XO><YS>0</YS><YO>60</YO></UDim2>\n'
        '\t\t\t\t\t\t<token name="SizeConstraint">1</token>\n'
        '\t\t\t\t\t\t<int name="ZOffset">0</int>\n'
        '\t\t\t\t\t\t<BinaryString name="AttributesSerialize"></BinaryString>\n'
        '\t\t\t\t\t\t<SecurityCapabilities name="Capabilities">0</SecurityCapabilities>\n'
        '\t\t\t\t\t\t<bool name="DefinesCapabilities">false</bool>\n'
        '\t\t\t\t\t\t<UniqueId name="HistoryId">00000000000000000000000000000000</UniqueId>\n'
        '\t\t\t\t\t\t<string name="Name">Sign</string>\n'
        '\t\t\t\t\t\t<int64 name="SourceAssetId">-1</int64>\n'
        '\t\t\t\t\t\t<SharedString name="Tags"></SharedString>\n'
        '\t\t\t\t\t\t<UniqueId name="UniqueId">' + sign_ref + '</UniqueId>\n'
        '\t\t\t\t\t</Properties>\n'
        '\t\t\t\t\t<Item class="TextLabel" referent="' + lbl_ref + '">\n'
        '\t\t\t\t\t\t<Properties>\n'
        '\t\t\t\t\t\t\t<Font name="FontFace"><Family><url>rbxassetid://12187365977</url></Family><Weight>700</Weight><Style>Normal</Style></Font>\n'
        '\t\t\t\t\t\t\t<bool name="RichText">false</bool>\n'
        '\t\t\t\t\t\t\t<string name="Text">' + zone["name"] + '  (Rarity: ' + zone["rarity"] + ')</string>\n'
        '\t\t\t\t\t\t\t<Color3 name="TextColor3"><R>1</R><G>1</G><B>1</B></Color3>\n'
        '\t\t\t\t\t\t\t<bool name="TextScaled">true</bool>\n'
        '\t\t\t\t\t\t\t<float name="TextSize">20</float>\n'
        '\t\t\t\t\t\t\t<float name="TextTransparency">0</float>\n'
        '\t\t\t\t\t\t\t<token name="TextTruncate">0</token>\n'
        '\t\t\t\t\t\t\t<bool name="TextWrapped">true</bool>\n'
        '\t\t\t\t\t\t\t<token name="TextXAlignment">2</token>\n'
        '\t\t\t\t\t\t\t<token name="TextYAlignment">1</token>\n'
        '\t\t\t\t\t\t\t<Color3 name="BackgroundColor3"><R>0</R><G>0</G><B>0</B></Color3>\n'
        '\t\t\t\t\t\t\t<float name="BackgroundTransparency">0.4</float>\n'
        '\t\t\t\t\t\t\t<bool name="Visible">true</bool>\n'
        '\t\t\t\t\t\t\t<int name="ZIndex">2</int>\n'
        + common("Label", lbl_ref) +
        '\t\t\t\t\t\t</Properties>\n'
        '\t\t\t\t\t</Item>\n'
        '\t\t\t\t</Item>\n'
        '\t\t\t</Item>\n'
    )
    return part, ref

def parse_zones(src_root):
    path = os.path.join(src_root, "ReplicatedStorage/Modules/ProgressionConfig.lua")
    txt = open(path, encoding="utf-8").read()
    zones = []
    for block in re.findall(r'\{\s*id\s*=\s*\d+.*?radius\s*=\s*\d+\s*\}', txt, re.S):
        name = re.search(r'name\s*=\s*"([^"]+)"', block)
        color = re.search(r'color\s*=\s*\{(\d+),\s*(\d+),\s*(\d+)\}', block)
        rarity = re.search(r'rarity\s*=\s*"([^"]+)"', block)
        center = re.search(r'center\s*=\s*\{(-?\d+),\s*(-?\d+),\s*(-?\d+)\}', block)
        radius = re.search(r'radius\s*=\s*(\d+)', block)
        req_str = re.search(r'req\s*=\s*\{([^}]*)\}', block)
        if not (name and color and center and radius):
            continue
        req = {}
        if req_str and req_str.group(1).strip():
            sm = re.search(r'size\s*=\s*(\d+)', req_str.group(1))
            if sm: req["size"] = int(sm.group(1))
            rm = re.search(r'rebirth\s*=\s*(\d+)', req_str.group(1))
            if rm: req["rebirth"] = int(rm.group(1))
        zones.append({
            "name": name.group(1),
            "color": [int(color.group(1)), int(color.group(2)), int(color.group(3))],
            "rarity": rarity.group(1),
            "req": req,
            "center": [int(center.group(1)), int(center.group(2)), int(center.group(3))],
            "radius": int(radius.group(1)),
        })
    return zones


def build_additions(base_text, src_root="src"):
    tag_re = re.compile(r'<Item class="([^"]+)" referent="([^"]+)">|(</Item>)')
    pos = 0
    stack = []
    items = {}
    while True:
        m = tag_re.search(base_text, pos)
        if not m:
            break
        if m.group(1) is not None:
            ref = m.group(2)
            parent = stack[-1][0] if stack else None
            stack.append((ref, m.start()))
            items[ref] = {"name": None, "parent": parent, "start": m.start()}
        else:
            if stack:
                ref, st = stack.pop()
                block = base_text[st:m.end()]
                nm = re.search(r'<string name="Name">([^<]*)</string>', block)
                items[ref]["name"] = nm.group(1) if nm else "?"
        pos = m.end()

    def children(ref): return [r for r in items if items[r]["parent"] == ref]
    def find_top(name):
        for r, d in items.items():
            if d["parent"] is None and d["name"] == name: return r
    def by_name(parent, name):
        for c in children(parent):
            if items[c]["name"] == name: return c

    Events = by_name(find_top("ReplicatedStorage"), "Events")
    Buttons = by_name(find_top("StarterGui"), "Buttons")
    Frames = by_name(find_top("StarterGui"), "Frames")
    Workspace = find_top("Workspace")

    existing = set(items.keys())
    try:
        existing.update(json.load(open("/tmp/existing_refs.json")))
    except Exception:
        pass

    additions = []
    for ev in ["Rebirth", "EquipSkin", "SkinList", "Leaderboard", "QuestFetch", "QuestClaim", "ZoneTeleport", "Admin"]:
        xml, _ = gen_event(ev, existing)
        additions.append((Events, xml))

    menus = ["Rebirth", "Skins", "Leaderboard", "Quests", "Zones", "Admin"]
    for i, name in enumerate(menus):
        xml, _ = gen_button(name, existing, "0.9", "%.3f" % (0.12 + i * 0.1))
        additions.append((Buttons, xml))

    frame_scripts = {
        "Rebirth": "StarterGui/Frames/Rebirth/LocalScript.lua",
        "Skins": "StarterGui/Frames/Skins/LocalScript.lua",
        "Leaderboard": "StarterGui/Frames/Leaderboard/LocalScript.lua",
        "Quests": "StarterGui/Frames/Quests/LocalScript.lua",
        "Zones": "StarterGui/Frames/Zones/LocalScript.lua",
        "Admin": "StarterGui/Frames/Admin/LocalScript.lua",
    }
    for name, path in frame_scripts.items():
        with open(os.path.join(src_root, path), encoding="utf-8") as f:
            src = f.read()
        xml, _ = gen_frame(name, existing, src)
        additions.append((Frames, xml))

    for z in parse_zones(src_root):
        xml, _ = gen_zone_platform(z, existing)
        additions.append((Workspace, xml))

    return additions

if __name__ == "__main__":
    txt = open("base_cube.rbxlx", encoding="utf-8", errors="replace").read()
    adds = build_additions(txt)
    print("generated", len(adds), "instances")
