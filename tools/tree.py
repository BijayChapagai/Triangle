#!/usr/bin/env python3
"""Dump the instance tree of an .rbxlx (names, classes, parent paths).

Used to plan the restructure (which scripts hold asset children, what can be
deleted safely) and by verify.py to assert the final tree shape.

Usage:
    python3 tools/tree.py [place.rbxlx] [--scripts] [--path StarterGui]
                          [--refs]        # report dangling <ref> referents
"""
import re, sys, argparse

ITEM_ANY = re.compile(r'<Item class="([^\"]+)\" referent=\"([^\"]+)\">|(</Item>)')
NAME_RE = re.compile(r'<string name="Name">([^<]*)</string>')
REF_RE = re.compile(r'<ref name="[^"]*">([^<]*)</ref>')


def parse(data):
    pos, stack = 0, []
    items, order = {}, []
    while True:
        m = ITEM_ANY.search(data, pos)
        if not m:
            break
        if m.group(1) is not None:
            ref = m.group(2)
            parent = stack[-1][0] if stack else None
            stack.append((ref, m.start()))
            items[ref] = {"class": m.group(1), "name": "?", "parent": parent,
                          "start": m.start(), "end": None, "children": []}
            order.append(ref)
        else:
            if stack:
                ref, st = stack.pop()
                block = data[st:m.end()]
                nm = NAME_RE.search(block)
                items[ref]["name"] = nm.group(1) if nm else "?"
                items[ref]["end"] = m.end()
                if items[ref]["parent"]:
                    items[items[ref]["parent"]]["children"].append(ref)
        pos = m.end()
    if stack:
        raise SystemExit("unbalanced <Item> tags: %d open" % len(stack))
    return items, order


def path_of(items, ref):
    parts = []
    while ref:
        parts.append(items[ref]["name"])
        ref = items[ref]["parent"]
    return "/".join(reversed(parts))


def roots(items, order):
    return [r for r in order if items[r]["parent"] is None]


def walk(items, ref, depth=0, out=None):
    out = out if out is not None else []
    it = items[ref]
    out.append((depth, it["class"], it["name"], ref))
    for c in it["children"]:
        walk(items, c, depth + 1, out)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("place", nargs="?", default="eat the cube.rbxlx")
    ap.add_argument("--scripts", action="store_true", help="only script instances")
    ap.add_argument("--path", default=None, help="only this subtree (by name path prefix)")
    ap.add_argument("--refs", action="store_true", help="report refs to missing instances")
    ap.add_argument("--classes", action="store_true", help="class histogram")
    args = ap.parse_args()

    data = open(args.place, encoding="utf-8", errors="replace").read()
    items, order = parse(data)
    print("file:", args.place, "items:", len(order))

    if args.classes:
        hist = {}
        for r in order:
            hist[items[r]["class"]] = hist.get(items[r]["class"], 0) + 1
        for k, v in sorted(hist.items(), key=lambda kv: -kv[1]):
            print("%6d  %s" % (v, k))

    if args.refs:
        missing = {}
        for m in REF_RE.finditer(data):
            ref = m.group(1)
            if ref and ref not in items:
                missing[ref] = missing.get(ref, 0) + 1
        if missing:
            print("DANGLING REFS:")
            for ref, n in sorted(missing.items(), key=lambda kv: -kv[1]):
                print("  %-40s x%d" % (ref, n))
        else:
            print("no dangling <ref> referents")

    script_classes = {"Script", "LocalScript", "ModuleScript", "CoreScript"}
    lines = []
    for root in roots(items, order):
        for depth, cls, name, ref in walk(items, root):
            p = path_of(items, ref)
            if args.path and not p.startswith(args.path):
                continue
            if args.scripts and cls not in script_classes:
                continue
            lines.append("%s%-13s %s   [%s]" % ("  " * depth, cls, name, ref))
    print("\n".join(lines))
    if args.scripts:
        print("script instances:", len(lines))


if __name__ == "__main__":
    main()
