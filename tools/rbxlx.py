#!/usr/bin/env python3
"""Low level .rbxlx toolkit.

Three jobs:
  1. parse()  - index every <Item>: class, name, parent, byte span
  2. Builder  - generate new instances from a REAL property template lifted out
                of the place, so every property keeps the exact type and shape
                Roblox writes. Hand-rolled property lists get this wrong in ways
                Studio silently ignores (UICorner.CornerRadius is a UDim, not an
                int; UIListLayout.Padding is a UDim, not a UDim2).
  3. Editor   - express every change (source override, rename, class change,
                delete, move, inject) as a non-overlapping byte span, apply them
                back-to-front, then validate.

CDATA payloads are masked before scanning: Lua sources in this place contain
markup-like text (e.g. '<font color="rgb(255,0,0)">' in the death screen) which
would otherwise be parsed as XML tags.
"""
import re, random

ITEM_ANY = re.compile(r'<Item class="([^"]+)" referent="([^"]+)">|(</Item>)')
NAME_RE = re.compile(r'<string name="Name">([^<]*)</string>')
SOURCE_RE = re.compile(r'<ProtectedString name="Source">.*?</ProtectedString>', re.S)
TAG = re.compile(r'<(/?)([A-Za-z0-9_]+)((?:\s+[A-Za-z0-9_:]+="[^"]*")*)\s*(/?)>')
ATTR = re.compile(r'([A-Za-z0-9_:]+)="([^"]*)"')
REF_RE = re.compile(r'<[Rr]ef name="[^"]*">([^<]*)</[Rr]ef>')
CDATA_RE = re.compile(r'<!\[CDATA\[.*?\]\]>', re.S)
CLASS_TAG = re.compile(r'<Item class="([^"]+)"')

TAB = "\t"

TYPE_TAGS = {
    "string", "bool", "int", "int64", "float", "double", "token", "Color3",
    "Color3uint8", "UDim2", "UDim", "Vector3", "Vector2", "CoordinateFrame",
    "BinaryString", "SharedString", "UniqueId", "raw", "ProtectedString",
    "Content", "SecurityCapabilities", "PhysicalProperties", "Font",
}


def mask_cdata(data):
    """Same length, CDATA payloads replaced by spaces."""
    return CDATA_RE.sub(lambda m: " " * len(m.group(0)), data)


# ---------------------------------------------------------------------------
# parsing
# ---------------------------------------------------------------------------

def parse(data):
    """Index every Item. `data` may be the masked copy; spans are identical."""
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
            items[ref] = {
                "class": m.group(1), "name": "?", "parent": parent,
                "start": m.start(), "end": None, "children": [],
            }
            order.append(ref)
        else:
            if not stack:
                raise ValueError("stray </Item> at %d" % m.start())
            ref, st = stack.pop()
            it = items[ref]
            it["end"] = m.end()
            nm = NAME_RE.search(data, st, m.end())
            it["name"] = nm.group(1) if nm else "?"
            if it["parent"]:
                items[it["parent"]]["children"].append(ref)
        pos = m.end()
    if stack:
        raise ValueError("unbalanced <Item> tags: %d still open" % len(stack))
    return items, order


def path_of(items, ref):
    parts = []
    while ref:
        parts.append(items[ref]["name"])
        ref = items[ref]["parent"]
    return "/".join(reversed(parts))


def roots(items, order):
    return [r for r in order if items[r]["parent"] is None]


def find_all(items, order, path):
    return [r for r in order if path_of(items, r) == path]


def find(items, order, path):
    hits = find_all(items, order, path)
    if not hits:
        raise KeyError("instance not found: " + path)
    return hits[0]


def descendants(items, ref):
    out = []
    for c in items[ref]["children"]:
        out.append(c)
        out.extend(descendants(items, c))
    return out


def service_ref(items, order, name):
    for r in order:
        if items[r]["parent"] is None and items[r]["name"] == name:
            return r
    raise KeyError("top level service not found: " + name)


def child_by_name(items, parent_ref, name):
    for c in items[parent_ref]["children"]:
        if items[c]["name"] == name:
            return c
    raise KeyError("%s has no child named %r" % (parent_ref, name))


# ---------------------------------------------------------------------------
# property scanning
# ---------------------------------------------------------------------------

def scan_props(block):
    """Top level property elements of one Item block (offsets relative to block)."""
    start = block.index("<Properties>") + len("<Properties>")
    # The FIRST </Properties>: the item's own block always precedes its children,
    # and rindex() would run the scan into nested <Item> elements.
    end = block.index("</Properties>", start)
    props, depth, cur = [], 0, None
    for m in TAG.finditer(block, start, end):
        closing, tag, attr_text, self_close = m.group(1), m.group(2), m.group(3), m.group(4)
        if closing:
            depth -= 1
            if depth == 0 and cur is not None:
                cur["end"] = m.end()
                cur["inner"] = block[cur["inner_start"]:m.start()]
                cur["raw"] = block[cur["start"]:m.end()]
                props.append(cur)
                cur = None
        elif self_close:
            if depth == 0:
                props.append({"tag": tag, "attrs": dict(ATTR.findall(attr_text)),
                              "start": m.start(), "end": m.end(), "inner": "",
                              "raw": block[m.start():m.end()]})
        else:
            if depth == 0:
                cur = {"tag": tag, "attrs": dict(ATTR.findall(attr_text)),
                       "start": m.start(), "inner_start": m.end()}
            depth += 1
    if depth != 0:
        raise ValueError("unbalanced property tags (depth %d)" % depth)
    return props


# ---------------------------------------------------------------------------
# value formatting
# ---------------------------------------------------------------------------

def _f(x):
    if isinstance(x, int) and not isinstance(x, bool):
        return str(x)
    x = float(x)
    # Roblox writes whole floats without a decimal point (<float>5</float>).
    return str(int(x)) if x.is_integer() else repr(x)


def fmt_value(tag, value):
    if tag == "string":
        return esc(value)
    if tag == "bool":
        return "true" if value else "false"
    if tag in ("int", "int64", "token"):
        return str(int(value))
    if tag in ("float", "double"):
        return _f(value)
    if tag == "Color3":
        r, g, b = value
        return "<R>%s</R><G>%s</G><B>%s</B>" % (_f(r / 255.0), _f(g / 255.0), _f(b / 255.0))
    if tag == "Color3uint8":
        r, g, b = value
        return str((int(r) << 16) | (int(g) << 8) | int(b))
    if tag == "UDim2":
        xs, xo, ys, yo = value
        return "<XS>%s</XS><XO>%d</XO><YS>%s</YS><YO>%d</YO>" % (_f(xs), int(xo), _f(ys), int(yo))
    if tag == "UDim":
        s, o = value
        return "<S>%s</S><O>%d</O>" % (_f(s), int(o))
    if tag == "Vector3":
        x, y, z = value
        return "<X>%s</X><Y>%s</Y><Z>%s</Z>" % (_f(x), _f(y), _f(z))
    if tag == "Vector2":
        x, y = value
        return "<X>%s</X><Y>%s</Y>" % (_f(x), _f(y))
    if tag == "CoordinateFrame":
        x, y, z = value
        return ("<X>%s</X><Y>%s</Y><Z>%s</Z>"
                "<R00>1</R00><R01>0</R01><R02>0</R02>"
                "<R10>0</R10><R11>1</R11><R12>0</R12>"
                "<R20>0</R20><R21>0</R21><R22>1</R22>") % (_f(x), _f(y), _f(z))
    if tag in ("BinaryString", "SharedString", "UniqueId", "raw", "Content",
               "SecurityCapabilities", "PhysicalProperties", "Font", "ProtectedString"):
        return value if isinstance(value, str) else ""
    raise ValueError("no formatter for property type %r (value %r)" % (tag, value))


def esc(t):
    return str(t).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def cdata(src):
    src = src.replace("\x00", "").replace("&#0;", "")
    return src.replace("]]>", "]] >")


def _split_override(value):
    """(tag, value): an explicit ('UDim', (0, 8)) pair, or None for 'use the
    template's own type'."""
    if isinstance(value, tuple) and len(value) == 2 and isinstance(value[0], str) \
            and value[0] in TYPE_TAGS:
        return value
    return None


# ---------------------------------------------------------------------------
# builder
# ---------------------------------------------------------------------------

COMMON_DROP = ("UniqueId", "HistoryId", "Tags", "SourceAssetId", "Name",
               "Capabilities", "DefinesCapabilities", "AttributesSerialize")


class Builder:
    def __init__(self, data, seed=20240607):
        self.data = data
        self.masked = mask_cdata(data)
        self.items, self.order = parse(self.masked)
        self.existing = set(self.items.keys())
        self._templates = {}
        self._rng = random.Random(seed)

    def uid(self):
        while True:
            ref = "RBX" + "".join(self._rng.choice("0123456789abcdef") for _ in range(32))
            if ref not in self.existing:
                self.existing.add(ref)
                return ref

    def guid(self):
        import uuid
        return "{" + str(uuid.UUID(int=self._rng.getrandbits(128), version=4)).upper() + "}"

    def template(self, cls):
        if cls in self._templates:
            return self._templates[cls]
        for ref in self.order:
            if self.items[ref]["class"] == cls:
                block = self.masked[self.items[ref]["start"]:self.items[ref]["end"]]
                props = scan_props(block)
                self._templates[cls] = props
                return props
        raise KeyError("no %s instance in the place to use as a property template" % cls)

    def _common_tail(self, ind, name, ref, extra=""):
        return (
            '{i}<BinaryString name="AttributesSerialize"></BinaryString>\n'
            '{i}<SecurityCapabilities name="Capabilities">0</SecurityCapabilities>\n'
            '{i}<bool name="DefinesCapabilities">false</bool>\n'
            '{i}<UniqueId name="HistoryId">00000000000000000000000000000000</UniqueId>\n'
            '{i}<string name="Name">{name}</string>\n'
            '{i}<int64 name="SourceAssetId">-1</int64>\n'
            '{i}<SharedString name="Tags"></SharedString>\n'
            '{i}<UniqueId name="UniqueId">{ref}</UniqueId>\n'
            '{extra}'
        ).format(i=ind, name=esc(name), ref=ref, extra=extra)

    def props_xml(self, cls, overrides, ind, drop=()):
        drop = set(drop) | set(COMMON_DROP)
        out, seen = [], set()
        for p in self.template(cls):
            name = p["attrs"].get("name")
            if name in drop:
                continue
            seen.add(name)
            if name in overrides:
                explicit = _split_override(overrides[name])
                tag, value = explicit if explicit else (p["tag"], overrides[name])
                out.append('%s<%s name="%s">%s</%s>\n' % (ind, tag, name, fmt_value(tag, value), tag))
            else:
                out.append(p["raw"] + "\n")
        for name, value in overrides.items():
            if name in seen or name in drop:
                continue
            explicit = _split_override(value)
            if not explicit:
                raise KeyError("property %r is not in the %s template; pass it as "
                               "(tag, value), e.g. ('UDim', (0, 8))" % (name, cls))
            tag, value = explicit
            out.append('%s<%s name="%s">%s</%s>\n' % (ind, tag, name, fmt_value(tag, value), tag))
        return "".join(out)

    def item(self, cls, name, overrides=None, children="", depth=3, ref=None):
        ref = ref or self.uid()
        pad, ind = TAB * depth, TAB * (depth + 1)
        body = self.props_xml(cls, overrides or {}, ind)
        xml = ('{p}<Item class="{cls}" referent="{ref}">\n{p}\t<Properties>\n'
               '{body}{tail}{p}\t</Properties>\n{children}{p}</Item>\n').format(
            p=pad, cls=cls, ref=ref, body=body,
            tail=self._common_tail(ind, name, ref), children=children)
        return xml, ref

    def bare_item(self, cls, name, props=(), children="", depth=3, ref=None):
        """Instance built from an explicit property list instead of a template.
        Only needed for classes the place does not already contain (Color3Value,
        IntValue, BoolValue, Configuration...), whose shapes are trivial.

        props: iterable of (tag, prop_name, value)
        """
        ref = ref or self.uid()
        pad, ind = TAB * depth, TAB * (depth + 1)
        body = "".join('%s<%s name="%s">%s</%s>\n' % (ind, tag, pname, fmt_value(tag, value), tag)
                       for tag, pname, value in props)
        xml = ('{p}<Item class="{cls}" referent="{ref}">\n{p}\t<Properties>\n'
               '{body}{tail}{p}\t</Properties>\n{children}{p}</Item>\n').format(
            p=pad, cls=cls, ref=ref, body=body,
            tail=self._common_tail(ind, name, ref), children=children)
        return xml, ref

    def script(self, cls, name, source, depth=3):
        ref = self.uid()
        pad, ind = TAB * depth, TAB * (depth + 1)
        src = '{i}<ProtectedString name="Source"><![CDATA[{s}]]></ProtectedString>\n'.format(
            i=ind, s=cdata(source))
        if cls == "ModuleScript":
            extra = '{i}<Content name="LinkedSource"><null></null></Content>\n'.format(i=ind)
            drop = ("Source", "LinkedSource", "CurrentEditor")
        else:
            extra = ('{i}<bool name="Disabled">false</bool>\n'
                     '{i}<Content name="LinkedSource"><null></null></Content>\n'
                     '{i}<token name="RunContext">0</token>\n').format(i=ind)
            drop = ("Source", "LinkedSource", "Disabled", "RunContext", "CurrentEditor")
        body = self.props_xml(cls, {}, ind, drop=drop + ("ScriptGuid",))
        tail = self._common_tail(ind, name, ref,
                                 extra='{i}<string name="ScriptGuid">{g}</string>\n'.format(
                                     i=ind, g=self.guid()))
        xml = ('{p}<Item class="{cls}" referent="{ref}">\n{p}\t<Properties>\n'
               '{src}{extra}{body}{tail}{p}\t</Properties>\n{p}</Item>\n').format(
            p=pad, cls=cls, ref=ref, src=src, extra=extra, body=body, tail=tail)
        return xml, ref


# ---------------------------------------------------------------------------
# span editor
# ---------------------------------------------------------------------------

class Editor:
    def __init__(self, data):
        self.data = data
        self.spans = []

    def replace(self, start, end, text, why=""):
        self.spans.append((start, end, text, why))

    def insert(self, at, text, why=""):
        self.spans.append((at, at, text, why))

    def delete(self, start, end, why=""):
        self.spans.append((start, end, "", why))

    def apply(self):
        self.spans.sort(key=lambda s: (s[0], s[1]))
        for i in range(1, len(self.spans)):
            ps, pe, _, pwhy = self.spans[i - 1]
            cs, _, _, cwhy = self.spans[i]
            if cs < pe:
                raise ValueError("overlapping edits: %r [%d:%d] vs %r [%d]"
                                 % (pwhy, ps, pe, cwhy, cs))
        out, pos = [], 0
        for s, e, text, _ in self.spans:
            out.append(self.data[pos:s])
            out.append(text)
            pos = e
        out.append(self.data[pos:])
        return "".join(out)


# ---------------------------------------------------------------------------
# source overrides / renames / class changes on existing instances
# ---------------------------------------------------------------------------

def source_span(data, item):
    """Byte span of the <ProtectedString name="Source">...</ProtectedString>
    element inside one item (offsets are absolute)."""
    m = SOURCE_RE.search(data, item["start"], item["end"])
    if not m:
        raise ValueError("instance has no Source property")
    return m.start(), m.end()


def source_block(new_source):
    return '<ProtectedString name="Source"><![CDATA[%s]]></ProtectedString>' % cdata(new_source)


def name_span(data, item):
    m = NAME_RE.search(data, item["start"], item["end"])
    if not m:
        raise ValueError("instance has no Name property")
    return m.start(), m.end()


def class_span(data, item):
    m = CLASS_TAG.search(data, item["start"], item["end"])
    return m.start(), m.end()


def prop_span(data, item, prop_name):
    """Span of one property element by name (used to drop Script-only properties
    when converting a Script into a ModuleScript or a Folder)."""
    block = data[item["start"]:item["end"]]
    for p in scan_props(mask_cdata(block)):
        if p["attrs"].get("name") == prop_name:
            return item["start"] + p["start"], item["start"] + p["end"]
    return None


# ---------------------------------------------------------------------------
# validation
# ---------------------------------------------------------------------------

def fix_mojibake(data):
    """Some emoji were serialised as one numeric char ref per UTF-8 byte, which
    shows up in game as 'ðŸ¤«'. Re-encode those runs as the real character."""
    run = re.compile(r'((?:&#(?:1[2-9][0-9]|2[0-4][0-9]|25[0-5]);)+)')

    def repl(m):
        codes = [int(c) for c in re.findall(r"&#(\d+);", m.group(1))]
        try:
            return bytes(codes).decode("utf-8")
        except UnicodeDecodeError:
            return m.group(0)

    return run.sub(repl, data)


def validate(data, expect_scripts=None, expect_localscripts=None):
    import xml.etree.ElementTree as ET
    problems = []
    try:
        ET.fromstring(data)
    except ET.ParseError as e:
        problems.append("XML is not well formed: %s" % e)
        return problems, {}

    masked = mask_cdata(data)
    items, order = parse(masked)

    # "null" is how Roblox serialises an empty reference, not a dangling one.
    dangling = set(m.group(1) for m in REF_RE.finditer(masked)
                   if m.group(1) and m.group(1) != "null") - set(items)
    if dangling:
        problems.append("dangling <ref> referents: %s" % sorted(dangling)[:6])

    scripts = [r for r in order if items[r]["class"] == "Script"]
    localscripts = [r for r in order if items[r]["class"] == "LocalScript"]
    if expect_scripts is not None and len(scripts) != expect_scripts:
        problems.append("expected %d Script, found %d: %s" % (
            expect_scripts, len(scripts), [path_of(items, r) for r in scripts][:8]))
    if expect_localscripts is not None and len(localscripts) != expect_localscripts:
        problems.append("expected %d LocalScript, found %d: %s" % (
            expect_localscripts, len(localscripts), [path_of(items, r) for r in localscripts][:8]))

    for r in order:
        if items[r]["class"] in ("Script", "LocalScript", "ModuleScript"):
            block = masked[items[r]["start"]:items[r]["end"]]
            if '<ProtectedString name="Source">' not in block:
                problems.append("script without Source: " + path_of(items, r))

    stats = {
        "items": len(order),
        "scripts": len(scripts),
        "localscripts": len(localscripts),
        "modulescripts": len([r for r in order if items[r]["class"] == "ModuleScript"]),
    }
    return problems, stats
