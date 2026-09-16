"""The Luau annotation stripper in verify.py.

verify.py parses every module with luaparser, which is a Lua 5.x parser and
cannot read Luau type annotations. strip_luau_types removes them first. That is
only safe if it removes *nothing else*, so these tests are mostly about the code
that must survive untouched: method calls, colons inside strings, table
constructors and the `type()` function.
"""
import glob
import os

import pytest

import verify
from conftest import SRC

pytest.importorskip("luaparser", reason="the syntax pass needs luaparser")

# Must come back byte identical: a colon here is never an annotation.
UNCHANGED = [
    'player:SetAttribute("Dead", true)',
    'local s = "Resets in %d:00"',
    "local t = { a = 1, b = 2 }",
    'if type(x) == "table" then y = 1 end',
    "local function f(a, b) return a[b] end",
    'local keyed = { ["a"] = 1 }',
    "local ok, err = pcall(f, a)",
    "for _, z in ipairs(zones) do print(z.name) end",
    'warn(("a: b"):format(1))',
    "local cb = function(item) item:Destroy() end",
    'local long = [[a: b]]',
    "Remotes.toClient(player, \"Notify\", text, \"info\")",
]

# Must lose the annotation, keep the code, and still parse.
STRIPPED = [
    "local x: number = 1\nreturn x",
    "local v: number | nil = nil\nreturn v",
    "local tbl: { number } = {}\nreturn tbl",
    "local map: { [string]: any } = {}\nreturn map",
    "function M.f(a: Player, b: number): boolean\n\treturn true\nend\nreturn M",
    "local function g(a: string?): (number)\n\treturn 1\nend\nreturn g",
    "local cb = function(item: BasePart): ()\n\titem:Destroy()\nend\nreturn cb",
    "type Zone = {\n\tid: number,\n\tname: string,\n}\nlocal z = 1\nreturn z",
    "export type Prefs = { [string]: boolean | number | string }\nlocal p = 1\nreturn p",
    "--!nonstrict\nlocal a = 1\nreturn a",
    "local a: number, b: string = 1, \"x\"\nreturn a",
    # the annotation must not eat the body that follows it
    "function h(a: number): number\n\tlocal y: number = a * 2\n\tplayer:SetAttribute(\"n\", y)\n\treturn y\nend\nreturn h",
]


@pytest.mark.parametrize("source", UNCHANGED)
def test_code_without_annotations_is_untouched(source):
    assert verify.strip_luau_types(source) == source


@pytest.mark.parametrize("source", STRIPPED)
def test_annotated_code_strips_and_parses(source):
    stripped = verify.strip_luau_types(source)
    assert stripped != source, "nothing was stripped"
    assert verify.syntax_errors("case.lua", source) is None, stripped
    # what the code actually does survives
    for token in ("player:SetAttribute", "item:Destroy"):
        if token in source:
            assert token in stripped


def test_stripping_is_idempotent():
    for source in STRIPPED + UNCHANGED:
        once = verify.strip_luau_types(source)
        assert verify.strip_luau_types(once) == once


def test_only_annotated_modules_are_touched():
    """The stripper must be a no-op on the rest of the tree.

    If this starts listing more files, the stripper is matching something it
    should not - which is how a syntax check quietly stops checking.
    """
    changed = []
    for path in sorted(glob.glob(os.path.join(SRC, "**", "*.lua"), recursive=True)):
        with open(path, encoding="utf-8") as f:
            source = f.read()
        if verify.strip_luau_types(source) != source:
            changed.append(os.path.basename(path))
    assert changed == ["GameConfig.lua"], changed


def test_masking_hides_string_and_comment_colons():
    masked = verify.mask_lua('local s = "a: b" -- c: d\nlocal t = 1')
    assert "a: b" not in masked and "c: d" not in masked
    assert "local t = 1" in masked
    assert len(masked) == len('local s = "a: b" -- c: d\nlocal t = 1')
