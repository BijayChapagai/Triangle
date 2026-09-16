"""verify.py has to fail when the place is broken.

These are mutation tests: each one damages the committed place in exactly the way
a real mistake would (a rename in Studio, a deleted remote, a hand-edited script)
and asserts that verify.py refuses it. A safety net that never fails is worse than
no safety net, because it makes the green light meaningless.
"""
import pytest

import rbxlx
from conftest import PLACE, SRC, VERIFY, read, run, write


@pytest.fixture(scope="session")
def raw():
    return read(PLACE)


def verify(path):
    return run(VERIFY, "--place", path, "--src", SRC, "--quiet", expect=None)


def span(raw, path):
    items, order = rbxlx.parse(rbxlx.mask_cdata(raw))
    ref = rbxlx.find(items, order, path)
    assert ref, "test target %s is not in the place" % path
    return items[ref]["start"], items[ref]["end"]


def replace_span(raw, path, fn):
    a, b = span(raw, path)
    patched = fn(raw[a:b])
    assert patched != raw[a:b], "the mutation did not change %s" % path
    return raw[:a] + patched + raw[b:]


def test_clean_place_passes(raw, tmp_path):
    code, out = verify(write(tmp_path / "clean.rbxlx", raw))
    assert code == 0, out


def test_renamed_asset_is_caught(raw, tmp_path):
    def fn(block):
        return block.replace('<string name="Name">Music</string>',
                             '<string name="Name">MusicRenamed</string>', 1)

    code, out = verify(write(tmp_path / "renamed.rbxlx",
                             replace_span(raw, "StarterGui/Buttons/Music", fn)))
    assert code == 1
    assert "StarterGui/Buttons/Music" in out


def test_deleted_remote_is_caught(raw, tmp_path):
    a, b = span(raw, "ReplicatedStorage/Events/Notify")
    code, out = verify(write(tmp_path / "no_notify.rbxlx", raw[:a] + raw[b:]))
    assert code == 1
    assert "Notify" in out


def test_undefined_shared_string_is_caught(raw, tmp_path):
    empty = rbxlx.empty_shared_string(raw)
    assert empty
    needle = '<SharedString name="Tags">%s</SharedString>' % empty
    assert needle in raw
    mutated = raw.replace(needle, '<SharedString name="Tags"></SharedString>', 1)
    code, out = verify(write(tmp_path / "bad_shared.rbxlx", mutated))
    assert code == 1
    assert "SharedString" in out


def test_edited_script_source_is_caught(raw, tmp_path):
    """The place copy of a module must be byte identical to src/."""
    def fn(block):
        assert "<![CDATA[" in block
        return block.replace("<![CDATA[", "<![CDATA[ ", 1)

    code, out = verify(write(tmp_path / "edited.rbxlx",
                             replace_span(raw, "ServerScriptService/Server", fn)))
    assert code == 1
    assert "Server" in out


def test_second_script_is_caught(raw, tmp_path):
    """One Script and one LocalScript is the architecture, not a preference."""
    a, b = span(raw, "ServerScriptService/Modules/Admin")
    block = raw[a:b].replace('<Item class="ModuleScript"', '<Item class="Script"', 1)
    assert block != raw[a:b]
    code, out = verify(write(tmp_path / "two_scripts.rbxlx", raw[:a] + block + raw[b:]))
    assert code == 1
    assert "Script" in out


def test_missing_place_setting_is_caught(raw, tmp_path):
    """CharacterAutoLoads must stay false or the cube architecture breaks.

    Deleting the property is the interesting case: Roblox then falls back to its
    default (true) and starts spawning its own avatars alongside the cube.
    """
    def fn(block):
        assert '<bool name="CharacterAutoLoads">false</bool>' in block
        return block.replace('<bool name="CharacterAutoLoads">false</bool>', "", 1)

    code, out = verify(write(tmp_path / "autospawn.rbxlx", replace_span(raw, "Players", fn)))
    assert code == 1
    assert "CharacterAutoLoads" in out


def test_wrong_place_setting_is_caught(raw, tmp_path):
    def fn(block):
        return block.replace('<bool name="CharacterAutoLoads">false</bool>',
                             '<bool name="CharacterAutoLoads">true</bool>', 1)

    code, out = verify(write(tmp_path / "autospawn_true.rbxlx", replace_span(raw, "Players", fn)))
    assert code == 1
    assert "CharacterAutoLoads" in out


# A DataStore handle opened at module scope throws during require() when API
# services are unavailable - Studio on an unpublished place - and takes the whole
# server down with it. That is exactly how the game broke in Studio once, so the
# shape is banned rather than merely discouraged.
def test_module_scope_datastore_is_banned():
    import verify

    src = 'local SizeStore = DataStoreService:GetOrderedDataStore("CubeLB_Size")\nreturn SizeStore\n'
    hits = [why for pattern, why in verify.BANNED if pattern.search(verify.strip_comments(src))]
    assert any("module scope" in why for why in hits), hits


def test_lazy_guarded_datastore_is_allowed():
    import verify

    src = (
        "local stores = {}\n"
        "local function getStore(name)\n"
        "\tlocal ok, store = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, name)\n"
        "\tif not ok then return nil end\n"
        "\tstores[name] = store\n"
        "\treturn store\n"
        "end\n"
        "return getStore\n"
    )
    hits = [why for pattern, why in verify.BANNED if pattern.search(verify.strip_comments(src))]
    assert hits == [], hits


def test_no_source_opens_a_datastore_at_module_scope():
    """The rule above is only worth having if the tree currently satisfies it."""
    import glob
    import os

    import verify

    offenders = []
    for path in sorted(glob.glob(os.path.join(SRC, "**", "*.lua"), recursive=True)):
        with open(path, encoding="utf-8") as f:
            source = verify.strip_comments(f.read())
        for pattern, why in verify.BANNED:
            if "module scope" in why and pattern.search(source):
                offenders.append(os.path.basename(path))
    assert offenders == [], offenders
