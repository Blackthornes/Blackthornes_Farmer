"""Checks for tools/harvest_import.py.

    python tools/test_harvest_import.py

The import script is the only thing in this repository that writes a tracked
file on its own -- it generates Data/Data_Harvested.lua and edits the TOC. A
file missing from the TOC never loads and the client says nothing about it, so
that edit is worth checking rather than trusting.

Everything runs against a throwaway copy of the repository in a temp directory,
so a failing test cannot leave edits behind in the real one.
"""

import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

SAVED = """
BlackthornesFarmerDB = {
\t["minimapAngle"] = 3.4906585039887,
\t["harvest"] = {
\t\t["Dalaran Apprentice|Silverpine Forest|The Sepulcher"] = {
\t\t\t["mob"] = "Dalaran Apprentice",
\t\t\t["zone"] = "Silverpine Forest",
\t\t\t["location"] = "The Sepulcher",
\t\t\t["minLevel"] = 21,
\t\t\t["maxLevel"] = 23,
\t\t\t["corpses"] = 47,
\t\t\t["coords"] = { 45.2, 68.1 },
\t\t\t["items"] = {
\t\t\t\t["Wool Cloth"] = {
\t\t\t\t\t["name"] = "Wool Cloth",
\t\t\t\t\t["count"] = 41,
\t\t\t\t\t["corpses"] = 29,
\t\t\t\t\t["id"] = 2592,
\t\t\t\t},
\t\t\t},
\t\t},
\t\t["Rot Hide Gnoll|Silverpine Forest|"] = {
\t\t\t["mob"] = "Rot Hide Gnoll",
\t\t\t["zone"] = "Silverpine Forest",
\t\t\t["minLevel"] = 20,
\t\t\t["maxLevel"] = 22,
\t\t\t["corpses"] = 8,
\t\t\t["items"] = {
\t\t\t\t["Wool Cloth"] = {
\t\t\t\t\t["name"] = "Wool Cloth",
\t\t\t\t\t["count"] = 3,
\t\t\t\t\t["corpses"] = 3,
\t\t\t\t},
\t\t\t},
\t\t},
\t},
}
"""

NO_HARVEST = 'BlackthornesFarmerDB = { ["minimapAngle"] = 3.49 }\n'

checks = 0
failures = []


def check(label, ok, detail=None):
    global checks
    checks += 1
    if not ok:
        failures.append("%s%s" % (label, "  -> %s" % detail if detail else ""))


def build_sandbox(saved_text):
    """A copy of the repo plus a fake WoW install holding `saved_text`."""
    sandbox = tempfile.mkdtemp(prefix="farmer-import-")

    repo = os.path.join(sandbox, "repo")
    shutil.copytree(ROOT, repo, ignore=shutil.ignore_patterns(".git"))

    # A real install nests the flavour folder and the account name, which is
    # what the script has to search through.
    saved_dir = os.path.join(
        sandbox, "client", "_classic_beta_", "WTF", "Account", "BLACKTHORNES",
        "SavedVariables")
    os.makedirs(saved_dir)

    with open(os.path.join(saved_dir, "Blackthornes_Farmer.lua"), "w",
              encoding="utf-8") as handle:
        handle.write(saved_text)

    return sandbox, repo, os.path.join(sandbox, "client")


def run_import(repo, client, *extra):
    return subprocess.run(
        [sys.executable, os.path.join(repo, "tools", "harvest_import.py"),
         "--client", client] + list(extra),
        capture_output=True, text=True, cwd=repo)


def main():
    # -- A normal import ------------------------------------------------------
    sandbox, repo, client = build_sandbox(SAVED)
    try:
        result = run_import(repo, client)
        check("the import succeeds", result.returncode == 0, result.stderr)

        generated = os.path.join(repo, "Data", "Data_Harvested.lua")
        check("it writes the data file", os.path.isfile(generated))

        text = open(generated, encoding="utf-8").read() if os.path.isfile(generated) else ""

        check("the file says it is generated",
              "tools/harvest_import.py" in text, text[:200])
        check("and warns against hand-editing", "Do not edit by hand" in text)
        check("it registers the item", 'name = "Wool Cloth"' in text)
        check("measured rows are marked Forever",
              'provenance = "forever"' in text)

        # 29 of 47 corpses is 62%, and the eight-corpse mob is under the
        # twenty-corpse floor, so exactly one rate should appear.
        check("a well-sampled mob gets its rate", "chance = 62" in text, text)
        check("a thin sample gets none", "too few for a rate" in text, text)
        check("exactly one rate is published",
              text.count("chance = ") == 1, text.count("chance = "))

        toc = open(os.path.join(repo, "Blackthornes_Farmer.toc"),
                   encoding="utf-8").read()
        check("the TOC picks up the generated file",
              "Data\\Data_Harvested.lua" in toc, toc)
        check("the TOC gains exactly one line",
              toc.count("Data_Harvested") == 1, toc.count("Data_Harvested"))

        # -- Running it twice --------------------------------------------------
        again = run_import(repo, client)
        check("a second import succeeds", again.returncode == 0, again.stderr)

        toc_again = open(os.path.join(repo, "Blackthornes_Farmer.toc"),
                         encoding="utf-8").read()
        check("and does not duplicate the TOC line",
              toc_again.count("Data_Harvested") == 1)
        check("and leaves the TOC otherwise unchanged", toc_again == toc)

        second = open(generated, encoding="utf-8").read()
        check("regenerating gives the same file", second == text)

        # -- The generated data actually loads ---------------------------------
        tests = subprocess.run(
            [sys.executable, os.path.join(repo, "tools", "runtests.py")],
            capture_output=True, text=True, cwd=repo)
        check("the addon's own tests pass against the generated data",
              tests.returncode == 0, tests.stderr[-800:])

        syntax = subprocess.run(
            [sys.executable, os.path.join(repo, "tools", "syntaxcheck.py")],
            capture_output=True, text=True, cwd=repo)
        check("the generated file parses as Lua 5.1",
              syntax.returncode == 0, syntax.stdout[-400:])
    finally:
        shutil.rmtree(sandbox, ignore_errors=True)

    # -- Nothing harvested yet ------------------------------------------------
    sandbox, repo, client = build_sandbox(NO_HARVEST)
    try:
        result = run_import(repo, client)
        check("an empty harvest is refused", result.returncode != 0)
        check("and says what to do about it",
              "Loot some corpses" in (result.stderr + result.stdout),
              result.stderr)
        check("it writes no data file",
              not os.path.isfile(os.path.join(repo, "Data", "Data_Harvested.lua")))

        toc = open(os.path.join(repo, "Blackthornes_Farmer.toc"),
                   encoding="utf-8").read()
        check("and does not touch the TOC", "Data_Harvested" not in toc)
    finally:
        shutil.rmtree(sandbox, ignore_errors=True)

    # -- No saved file at all -------------------------------------------------
    empty = tempfile.mkdtemp(prefix="farmer-empty-")
    sandbox, repo, _ = build_sandbox(SAVED)
    try:
        result = run_import(repo, empty)
        check("a missing saved file is refused", result.returncode != 0)
        check("and explains how to produce one",
              "Log out of WoW" in (result.stderr + result.stdout), result.stderr)
    finally:
        shutil.rmtree(sandbox, ignore_errors=True)
        shutil.rmtree(empty, ignore_errors=True)

    # -- The Windows launcher and its shortcut --------------------------------
    #
    # None of this can be executed here or in CI, so it is checked structurally
    # instead. The point is to catch the things that rot silently: a renamed
    # script the batch file still calls, or line endings normalised to LF,
    # which makes a batch file with labels misbehave in ways that look like the
    # import itself is broken.

    launcher = os.path.join(ROOT, "Import Harvest.bat")
    shortcut = os.path.join(ROOT, "tools", "make_shortcut.ps1")
    icon = os.path.join(ROOT, "tools", "farmer.ico")

    check("the launcher exists", os.path.isfile(launcher))
    check("the shortcut maker exists", os.path.isfile(shortcut))
    check("the icon exists", os.path.isfile(icon))

    if os.path.isfile(launcher):
        raw = open(launcher, "rb").read()
        text = raw.decode("utf-8")

        check("the launcher has CRLF endings",
              b"\r\n" in raw and b"\n" not in raw.replace(b"\r\n", b""))
        check("the launcher calls the import script",
              "tools\\harvest_import.py" in text)
        check("the launcher waits before closing",
              re.search(r"(?mi)^\s*pause\s*$", text) is not None)

        # Every goto has to land somewhere. Comments are stripped first: "goto"
        # appears in the prose at the top explaining why this file uses it.
        code = "\n".join(line for line in text.splitlines()
                          if not re.match(r"(?i)^\s*rem\b", line))
        labels = set(m.group(1).lower() for m in
                     re.finditer(r"(?mi)^\s*:([A-Za-z_]\w*)\s*$", code))
        gotos = [m.group(1).lower() for m in
                 re.finditer(r"(?mi)\bgoto\s+([A-Za-z_]\w*)", code)]
        missing = sorted(set(g for g in gotos if g not in labels))

        check("every goto in the launcher has a label", not missing, missing)
        check("the launcher actually branches", len(labels) > 3, len(labels))

    if os.path.isfile(shortcut):
        raw = open(shortcut, "rb").read()
        text = raw.decode("utf-8")

        check("the shortcut maker has CRLF endings",
              b"\r\n" in raw and b"\n" not in raw.replace(b"\r\n", b""))
        check("it points at the launcher by its real name",
              "Import Harvest.bat" in text)
        check("it points at the icon by its real name", "farmer.ico" in text)

    if os.path.isfile(icon):
        data = open(icon, "rb").read()
        reserved, kind, count = struct.unpack("<HHH", data[:6])

        check("the icon is a real .ico", reserved == 0 and kind == 1,
              (reserved, kind))
        check("it carries several sizes", count >= 4, count)

        sizes, in_bounds = [], True

        for index in range(count):
            entry = 6 + 16 * index
            width, _, _, _, _, _, length, offset = struct.unpack(
                "<BBBBHHII", data[entry:entry + 16])
            sizes.append(width or 256)
            if offset + length > len(data):
                in_bounds = False

        check("every icon entry is inside the file", in_bounds)
        check("it has a 16 pixel size for the taskbar", 16 in sizes, sizes)
        check("it has a 256 pixel size for large views", 256 in sizes, sizes)

        # The generator and the committed file must not drift apart.
        sandbox, repo, _ = build_sandbox(SAVED)
        try:
            regenerated = subprocess.run(
                [sys.executable, os.path.join(repo, "tools", "make_icon.py")],
                capture_output=True, text=True, cwd=repo)
            check("the icon generator runs", regenerated.returncode == 0,
                  regenerated.stderr[-400:])
            check("and reproduces the committed icon exactly",
                  open(os.path.join(repo, "tools", "farmer.ico"), "rb").read() == data)
        finally:
            shutil.rmtree(sandbox, ignore_errors=True)

    for failure in failures:
        print("FAIL -- %s" % failure, file=sys.stderr)

    print("  harvest_import: %d checks, %d failure(s)" % (checks, len(failures)))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
