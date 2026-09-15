#!/usr/bin/env python3
"""Recombine the place: apply src/ script overrides (by referent), inject new
scripts and generated instances, validate, and write the final .rbxlx."""
import re, json, os, importlib.util
import xml.etree.ElementTree as ET

BASE = "base_cube.rbxlx"
OUT = "eat the cube.rbxlx"
SRC = "src"

# ---- parse base to map referents -> block bounds ----
def parse_items(data):
    tag_re = re.compile(r'<Item class="([^"]+)" referent="([^"]+)">|(</Item>)')
    pos = 0
    stack = []
    items = {}
    order = []
    while True:
        m = tag_re.search(data, pos)
        if not m:
            break
        if m.group(1) is not None:
            ref = m.group(2)
            stack.append((ref, m.start()))
            items[ref] = {"name": None, "parent": (stack[-2][0] if len(stack) > 1 else None),
                          "start": m.start(), "end": None}
            order.append(ref)
        else:
            if stack:
                ref, st = stack.pop()
                items[ref]["end"] = m.end()
                block = data[st:m.end()]
                nm = re.search(r'<string name="Name">([^<]*)</string>', block)
                items[ref]["name"] = nm.group(1) if nm else "?"
        pos = m.end()
    return items, order

def block_bounds(data, ref):
    items, _ = parse_items(data)
    return items[ref]["start"], items[ref]["end"]

def sanitize(text):
    # Remove literal NUL bytes and invalid numeric char references (from Roblox
    # serializing control chars in comments, e.g. inside ProfileService).
    return text.replace("\x00", "").replace("&#0;", "").replace("&#x0;", "")

def replace_source(data, ref, new_source):
    s, e = block_bounds(data, ref)
    block = data[s:e]
    new_source = sanitize(new_source)
    new_block = re.sub(r'<ProtectedString name="Source">.*?</ProtectedString>',
                       '<ProtectedString name="Source"><![CDATA[' + new_source + ']]></ProtectedString>',
                       block, count=1, flags=re.S)
    return data[:s] + new_block + data[e:]

def gen_uuid():
    import uuid
    return "{" + str(uuid.uuid4()).upper() + "}"

def gen_new_script(class_, name, source, existing):
    source = sanitize(source)
    import random
    while True:
        ref = "RBX" + "".join(random.choice("0123456789abcdef") for _ in range(32))
        if ref not in existing:
            existing.add(ref)
            break
    src = source.replace("]]>", "]] >")
    if class_ == "ModuleScript":
        inner = (
            '\t\t\t\t<Content name="LinkedSource"><null></null></Content>\n'
            f'\t\t\t\t<ProtectedString name="Source"><![CDATA[{src}]]></ProtectedString>\n'
            f'\t\t\t\t<string name="ScriptGuid">{gen_uuid()}</string>\n'
        )
    else:
        inner = (
            f'\t\t\t\t<ProtectedString name="Source"><![CDATA[{src}]]></ProtectedString>\n'
            '\t\t\t\t<bool name="Disabled">false</bool>\n'
            '\t\t\t\t<Content name="LinkedSource"><null></null></Content>\n'
            '\t\t\t\t<token name="RunContext">0</token>\n'
            f'\t\t\t\t<string name="ScriptGuid">{gen_uuid()}</string>\n'
        )
    return (
        f'\t\t\t<Item class="{class_}" referent="{ref}">\n'
        '\t\t\t\t<Properties>\n'
        + inner +
        '\t\t\t\t\t<BinaryString name="AttributesSerialize"></BinaryString>\n'
        '\t\t\t\t\t<SecurityCapabilities name="Capabilities">0</SecurityCapabilities>\n'
        '\t\t\t\t\t<bool name="DefinesCapabilities">false</bool>\n'
        '\t\t\t\t\t<UniqueId name="HistoryId">00000000000000000000000000000000</UniqueId>\n'
        f'\t\t\t\t\t<string name="Name">{name}</string>\n'
        '\t\t\t\t\t<int64 name="SourceAssetId">-1</int64>\n'
        '\t\t\t\t\t<SharedString name="Tags"></SharedString>\n'
        f'\t\t\t\t\t<UniqueId name="UniqueId">{ref}</UniqueId>\n'
        '\t\t\t\t</Properties>\n'
        '\t\t\t</Item>\n'
    ), ref

def main():
    data = open(BASE, encoding="utf-8", errors="replace").read()
    items, _ = parse_items(data)
    existing = set(items.keys())
    try:
        existing.update(json.load(open("/tmp/existing_refs.json")))
    except Exception:
        pass

    # 1) Apply src/ overrides (existing scripts)
    manifest = json.load(open(os.path.join(SRC, "manifest.json")))
    overrides = 0
    for path, ref in manifest.items():
        fp = os.path.join(SRC, path + ".lua")
        if not os.path.exists(fp):
            continue
        src = open(fp, encoding="utf-8").read()
        data = replace_source(data, ref, src)
        overrides += 1
    print("applied", overrides, "script overrides")

    # 2) Inject new server/module scripts
    SSS = "RBX427793D7346F4801B2E16D0A3F74BB09"   # ServerScriptService
    MOD = "RBX9AA31658F3F34F50A3104A3DD01AF2A0"  # ReplicatedStorage.Modules
    new_scripts = [
        (SSS, "ModuleScript", "Progression", "ServerScriptService/Progression.lua"),
        (MOD, "ModuleScript", "ProgressionConfig", "ReplicatedStorage/Modules/ProgressionConfig.lua"),
        (SSS, "ModuleScript", "FoodSpawner", "ServerScriptService/FoodSpawner.lua"),
        (SSS, "ModuleScript", "ProgressionServer", "ServerScriptService/ProgressionServer.lua"),
        (SSS, "ModuleScript", "AdminServer", "ServerScriptService/AdminServer.lua"),
    ]
    inserts = []  # (parent_ref, xml)
    for parent, cls, name, path in new_scripts:
        src = open(os.path.join(SRC, path), encoding="utf-8").read()
        xml, _ = gen_new_script(cls, name, src, existing)
        inserts.append((parent, xml))

    # 3) Generated instances (events, buttons, frames, zones)
    import instances
    inserts.extend(instances.build_additions(data, SRC))

    # 4) Insert all additions from end -> start to preserve offsets
    insert_jobs = []
    for parent_ref, xml in inserts:
        s, e = block_bounds(data, parent_ref)
        insert_jobs.append((e, xml))
    insert_jobs.sort(reverse=True)
    for e, xml in insert_jobs:
        # insert before the parent's closing </Item>
        data = data[:e-8] + xml + data[e-8:]

    # 5) Validate + write
    data = sanitize(data)
    ET.fromstring(data)
    print("XML well-formed: OK")
    open(OUT, "w", encoding="utf-8").write(data)
    print("wrote", OUT, "size MB", round(len(data)/1e6, 2))

    # quick counts
    print("RemoteEvents:", data.count('class="RemoteEvent"'))
    print("Script+LocalScript+ModuleScript:",
          data.count('class="Script"') + data.count('class="LocalScript"') + data.count('class="ModuleScript"'))
    print("Frames:", data.count('class="Frame"'))

if __name__ == "__main__":
    main()
