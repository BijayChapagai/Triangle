"""Shared paths and helpers for the tool tests.

There is no __init__.py here, so pytest puts this directory on sys.path and the
tests can `from conftest import ...`. tools/ is added to sys.path so the tools
themselves are importable as modules (rbxlx, content, diff_place).
"""
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TOOLS = os.path.join(ROOT, "tools")
SRC = os.path.join(ROOT, "src")
PLACE = os.path.join(ROOT, "eat the cube.rbxlx")
BASE = os.path.join(ROOT, "base_cube.rbxlx")
ORIGINAL = os.path.join(ROOT, "eat the traingles.rbxlx")   # the place the HUD was copied from
GAMEDATA = os.path.join(SRC, "gamedata.json")
BUILD = os.path.join(TOOLS, "build.py")
VERIFY = os.path.join(TOOLS, "verify.py")
DIFF = os.path.join(TOOLS, "diff_place.py")

sys.path.insert(0, TOOLS)


def run(*args, **kwargs):
    """Run a tool as a subprocess. Returns (returncode, combined output).

    expect=None means "any exit code is fine"; otherwise a non-matching exit
    code fails the test with the captured output, which is almost always the
    interesting part.
    """
    expect = kwargs.pop("expect", 0)
    assert not kwargs, "unexpected kwargs: %s" % sorted(kwargs)
    proc = subprocess.run([sys.executable] + [str(a) for a in args],
                          cwd=ROOT, capture_output=True, text=True)
    out = proc.stdout + proc.stderr
    if expect is not None and proc.returncode != expect:
        raise AssertionError("%s exited %d, expected %d\n%s"
                             % (os.path.basename(str(args[0])), proc.returncode, expect, out))
    return proc.returncode, out


def read(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        return f.read()


def write(path, text):
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    return str(path)


def digest(path):
    import hashlib
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()
