"""The build itself: deterministic, self-validating, and matching the commit."""
import os

import pytest

import rbxlx
from conftest import BUILD, PLACE, digest, read, run


@pytest.fixture(scope="session")
def built(tmp_path_factory):
    out = str(tmp_path_factory.mktemp("build") / "built.rbxlx")
    run(BUILD, "--out", out)
    return out


def test_committed_place_is_current(built):
    """The binary in git must be exactly what src/ builds.

    This is the check that catches "I edited a module and forgot to rebuild".
    """
    assert digest(built) == digest(PLACE), (
        "eat the cube.rbxlx is stale: run `python3 tools/build.py` and commit it")


def test_build_is_deterministic(built, tmp_path):
    second = str(tmp_path / "second.rbxlx")
    run(BUILD, "--out", second)
    assert digest(second) == digest(built), "the build is not reproducible (unseeded randomness?)"


def test_build_validates(built):
    problems, stats = rbxlx.validate(read(built), expect_scripts=1, expect_localscripts=1)
    assert not problems
    # 10 server modules + ProfileService, 11 client modules, 11 menus, GameConfig,
    # UiModule and the third party FormatNumberAlt subtree.
    assert stats["modulescripts"] >= 40


def test_check_mode_writes_nothing(tmp_path):
    out = str(tmp_path / "should_not_exist.rbxlx")
    _code, text = run(BUILD, "--out", out, "--check")
    assert "nothing written" in text
    assert not os.path.exists(out)


def test_shared_strings_all_resolve(built):
    """An undefined md5 stops Roblox from opening the place at all."""
    raw = read(built)
    defined = set(m.group(1) for m in rbxlx.SHARED_DEF_RE.finditer(raw))
    referenced = set(rbxlx.SHARED_REF_RE.findall(raw))
    assert referenced, "no SharedString references found - the regexes are wrong"
    assert "" not in referenced, "a SharedString reference has an empty md5"
    assert referenced <= defined, "undefined md5: %s" % sorted(referenced - defined)


def test_every_generated_instance_has_tags(built):
    """The Tags reference is what the empty-md5 bug looked like; assert the shape."""
    raw = read(built)
    empty = rbxlx.empty_shared_string(raw)
    assert empty, "the place defines no zero-length SharedString blob"
    tags = rbxlx.SHARED_REF_RE.findall(raw)
    assert tags.count(empty) > 1000, "most instances should reference the empty Tags blob"


def test_builder_refuses_place_without_empty_blob(built):
    raw = read(built)
    start = raw.index("<SharedStrings>")
    end = raw.index("</SharedStrings>") + len("</SharedStrings>")
    with pytest.raises(RuntimeError, match="empty SharedString"):
        rbxlx.Builder(raw[:start] + raw[end:])


def test_build_fails_on_missing_source(tmp_path):
    """A script in the plan with no src file must be a hard error, not a stub."""
    missing = str(tmp_path / "nowhere.rbxlx")
    _code, text = run(BUILD, "--out", missing, "--base", str(tmp_path / "no_such_base.rbxlx"),
                      expect=None)
    assert _code != 0, "building from a missing base should fail"
    assert not os.path.exists(missing)
