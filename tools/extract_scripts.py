#!/usr/bin/env python3
"""Extract every Script/LocalScript/ModuleScript from the base place into src/
mirroring the in-place hierarchy, and write src/manifest.json (path -> referent)."""
import re, os, json

BASE = "base_cube.rbxlx"
SRC = "src"
os.makedirs(SRC, exist_ok=True)

data = open(BASE, encoding="utf-8", errors="replace").read()
tag_re = re.compile(r'<Item class="([^"]+)" referent="([^"]+)">|(</Item>)')
pos = 0
stack = []          # list of (ref, start)
items = {}          # ref -> dict(class,name,parent,start,end)
order = []
while True:
    m = tag_re.search(data, pos)
    if not m:
        break
    if m.group(1) is not None:
        ref, cls = m.group(2), m.group(1)
        parent = stack[-1][0] if stack else None
        stack.append((ref, m.start()))
        items[ref] = {"class": cls, "name": None, "parent": parent, "start": m.start(), "end": None}
        order.append(ref)
    else:
        if stack:
            ref, st = stack.pop()
            items[ref]["end"] = m.end()
            block = data[st:m.end()]
            nm = re.search(r'<string name="Name">([^<]*)</string>', block)
            items[ref]["name"] = nm.group(1) if nm else "?"
    pos = m.end()

def path_of(ref):
    """Build a slash path from the top-level service down to this instance."""
    chain = []
    cur = ref
    while cur is not None and cur in items:
        chain.append(items[cur]["name"])
        cur = items[cur]["parent"]
    chain.reverse()
    return "/".join(chain)

scripts = [r for r in order if items[r]["class"] in ("Script", "LocalScript", "ModuleScript")]
manifest = {}
used = set()
for r in scripts:
    block = data[items[r]["start"]:items[r]["end"]]
    src = re.search(r'<ProtectedString name="Source">(.*?)</ProtectedString>', block, re.S)
    source = src.group(1) if src else ""
    # strip CDATA wrapper if present
    c = re.search(r'<!\[CDATA\[(.*)\]\]>', source, re.S)
    if c:
        source = c.group(1)
    p = path_of(r)
    # ensure unique filename
    fpath = os.path.join(SRC, p + ".lua")
    base, ext = fpath[:-4], ".lua"
    i = 1
    while fpath in used:
        fpath = f"{base}_{i}{ext}"
        i += 1
    used.add(fpath)
    os.makedirs(os.path.dirname(fpath), exist_ok=True)
    with open(fpath, "w", encoding="utf-8") as f:
        f.write(source)
    # manifest key = relative path without extension
    key = fpath[len(SRC)+1:-4]
    manifest[key] = r

with open(os.path.join(SRC, "manifest.json"), "w") as f:
    json.dump(manifest, f, indent=2)

print(f"Extracted {len(scripts)} scripts into {SRC}/")
print(f"Manifest entries: {len(manifest)}")
