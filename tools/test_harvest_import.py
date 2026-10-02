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

CARRYOVER_ID = re.search(
    r'id = "([^"]+)"',
    open(os.path.join(ROOT, "Data", "Harvest_Carryover.lua"), encoding="utf-8").read()
).group(1)


def stamped(text):
    """`text` as saved by a login that has already added the carryover."""
    return text.replace(
        "BlackthornesFarmerDB = {",
        'BlackthornesFarmerDB = {\n\t["harvestCarryover"] = "%s",' % CARRYOVER_ID, 1)


NO_HARVEST = stamped('BlackthornesFarmerDB = { ["minimapAngle"] = 3.49 }\n')

# A smaller harvest than SAVED, with coins in its loot recorded by an old
# version: what the import has to refuse to publish over a bigger one, and the
# coin filter in one file.
LATER = """
BlackthornesFarmerDB = {
\t["harvest"] = {
\t\t["Dalaran Apprentice|Silverpine Forest|The Sepulcher"] = {
\t\t\t["mob"] = "Dalaran Apprentice",
\t\t\t["zone"] = "Silverpine Forest",
\t\t\t["location"] = "The Sepulcher",
\t\t\t["minLevel"] = 19,
\t\t\t["maxLevel"] = 24,
\t\t\t["corpses"] = 10,
\t\t\t["items"] = {
\t\t\t\t["Wool Cloth"] = {
\t\t\t\t\t["name"] = "Wool Cloth",
\t\t\t\t\t["count"] = 6,
\t\t\t\t\t["corpses"] = 5,
\t\t\t\t\t["id"] = 2592,
\t\t\t\t},
\t\t\t\t["14 Copper"] = {
\t\t\t\t\t["name"] = "14 Copper",
\t\t\t\t\t["count"] = 3,
\t\t\t\t\t["corpses"] = 3,
\t\t\t\t},
\t\t\t},
\t\t},
\t\t["Moonrage Whitescalp|Silverpine Forest|"] = {
\t\t\t["mob"] = "Moonrage Whitescalp",
\t\t\t["zone"] = "Silverpine Forest",
\t\t\t["minLevel"] = 18,
\t\t\t["maxLevel"] = 19,
\t\t\t["corpses"] = 6,
\t\t\t["items"] = {
\t\t\t\t["Wolf Meat"] = {
\t\t\t\t\t["name"] = "Wolf Meat",
\t\t\t\t\t["count"] = 4,
\t\t\t\t\t["corpses"] = 4,
\t\t\t\t\t["id"] = 1015,
\t\t\t\t},
\t\t\t},
\t\t},
\t},
}
"""



def with_fishing(text, casts, fish):
    """`text` with a fishing record: one open-water spot in Elwynn Forest,
    `casts` casts, `fish` of them landing Raw Brilliant Smallfish."""
    return text.replace(
        "BlackthornesFarmerDB = {",
        """BlackthornesFarmerDB = {
\t["fishing"] = { ["spots"] = {
\t\t["Elwynn Forest|Crystal Lake|"] = {
\t\t\t["zone"] = "Elwynn Forest", ["location"] = "Crystal Lake",
\t\t\t["casts"] = %d, ["minSkill"] = 40, ["maxSkill"] = 52,
\t\t\t["items"] = { ["Raw Brilliant Smallfish"] = {
\t\t\t\t["casts"] = %d, ["count"] = %d, ["id"] = 6291 } },
\t\t},
\t} },""" % (casts, fish, fish), 1)


def with_herb(text):
    """`text` with Peacebloom on the first mob, as a version before
    Logic/Gathering.lua recorded a herb picked with a corpse targeted."""
    return text.replace(
        '\t\t\t\t["Wool Cloth"] = {',
        """\t\t\t\t["Peacebloom"] = {
\t\t\t\t\t["name"] = "Peacebloom",
\t\t\t\t\t["count"] = 30,
\t\t\t\t\t["corpses"] = 25,
\t\t\t\t\t["id"] = 2447,
\t\t\t\t},
\t\t\t\t["Wool Cloth"] = {""", 1)


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

    # The generated data file is deliberately left behind. It is Trent's real
    # harvest, and a sandbox that inherited it would be testing against his
    # data instead of its own.
    shutil.copytree(ROOT, repo,
                    ignore=shutil.ignore_patterns(".git", "Data_Harvested.lua"))

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


def write_saved(client, text):
    """Replace what the fake client last wrote at logout."""
    path = os.path.join(
        client, "_classic_beta_", "WTF", "Account", "BLACKTHORNES",
        "SavedVariables", "Blackthornes_Farmer.lua")

    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text)

    return path


def main():
    # -- A normal import ------------------------------------------------------
    sandbox, repo, client = build_sandbox(stamped(SAVED))
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
        check("55 corpses are recorded", "55 corpses" in result.stdout,
              result.stdout)
        check("the listing says it is the running total",
              "everything harvested so far" in result.stdout, result.stdout)

        # 29 of 47 corpses is 62%, and the eight-corpse mob is under the
        # twenty-corpse floor, so exactly one rate should appear.
        check("a well-sampled mob gets its rate", "chance = 62" in text, text)
        check("a thin sample gets none", "too few for a rate" in text, text)
        check("exactly one rate is published",
              text.count("chance = ") == 1, text.count("chance = "))

        # The carryover is already inside the saved harvest; the import must
        # not add it a second time.
        check("the carryover is not added again", "Baron Longshore" not in text)

        toc = open(os.path.join(repo, "Blackthornes_Farmer.toc"),
                   encoding="utf-8").read()
        check("the TOC lists the generated file",
              "Data\\Data_Harvested.lua" in toc, toc)
        check("exactly once",
              toc.count("Data_Harvested") == 1, toc.count("Data_Harvested"))

        # -- Running it twice --------------------------------------------------
        #
        # The saved file is the total, so reading it twice writes the same
        # thing twice. Double-clicking the desktop shortcut again is harmless.
        again = run_import(repo, client)
        check("a second import succeeds", again.returncode == 0, again.stderr)
        check("and regenerates the same file",
              open(generated, encoding="utf-8").read() == text)
        check("and leaves the TOC unchanged",
              open(os.path.join(repo, "Blackthornes_Farmer.toc"),
                   encoding="utf-8").read() == toc)

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

        # -- A smaller harvest is not published over a bigger one --------------
        #
        # The saved harvest only grows. A smaller one means a reset or a client
        # that has stopped reading saved variables back, and the repository
        # keeps what it has until somebody says otherwise.
        write_saved(client, stamped(LATER))
        smaller = run_import(repo, client)

        check("a smaller harvest is refused", smaller.returncode != 0,
              smaller.stdout)
        check("and says why",
              "was built from 55" in (smaller.stdout + smaller.stderr),
              smaller.stderr)
        check("THE PUBLISHED DATA SURVIVES IT",
              open(generated, encoding="utf-8").read() == text)

        allowed = run_import(repo, client, "--allow-smaller")
        check("--allow-smaller writes it anyway", allowed.returncode == 0,
              allowed.stderr)

        written = open(generated, encoding="utf-8").read()
        check("the smaller harvest is what was written", "Wolf Meat" in written)
        check("coins never reach the data file", "14 Copper" not in written,
              written)
    finally:
        shutil.rmtree(sandbox, ignore_errors=True)

    # -- Fishing ----------------------------------------------------------------
    #
    # Catches go into the same file as fishing rows, and their casts are held
    # to the same never-shrink rule as corpses.
    sandbox, repo, client = build_sandbox(stamped(with_fishing(SAVED, 25, 20)))
    try:
        generated = os.path.join(repo, "Data", "Data_Harvested.lua")
        result = run_import(repo, client)
        check("an import with fishing succeeds", result.returncode == 0, result.stderr)

        text = open(generated, encoding="utf-8").read() if os.path.isfile(generated) else ""

        check("the header counts the casts", "-- 25 fishing casts." in text, text[:300])
        check("the listing mentions them", "25 fishing casts" in result.stdout, result.stdout)
        check("the catch is a fishing row",
              'kind = "fishing", name = "open water", zone = "Elwynn Forest", '
              'location = "Crystal Lake"' in text, text)
        check("with the item id", "id = 6291" in text, text)
        check("20 of 25 casts is 80%", "chance = 80" in text, text)
        check("the skill is noted", "fishing skill 40-52" in text, text)
        check("the mob rows are still there", "chance = 62" in text, text)

        write_saved(client, stamped(with_fishing(SAVED, 10, 4)))
        fewer = run_import(repo, client)

        check("fewer casts are refused", fewer.returncode != 0, fewer.stdout)
        check("and it says why",
              "was built from 25" in (fewer.stdout + fewer.stderr), fewer.stderr)
        check("THE PUBLISHED FISHING SURVIVES IT",
              open(generated, encoding="utf-8").read() == text)

        check("--allow-smaller still writes it",
              run_import(repo, client, "--allow-smaller").returncode == 0)
        check("and the smaller record is what was written",
              "-- 10 fishing casts." in open(generated, encoding="utf-8").read())

        tests = subprocess.run(
            [sys.executable, os.path.join(repo, "tools", "runtests.py")],
            capture_output=True, text=True, cwd=repo)
        check("the addon's tests pass with fishing rows in the data",
              tests.returncode == 0, tests.stderr[-800:])
    finally:
        shutil.rmtree(sandbox, ignore_errors=True)

    # -- A herb credited to a mob -----------------------------------------------
    #
    # Herbs and ore count per node. One an older version recorded on a mob is
    # left out of the data file, and the mob's own drops are still written.
    sandbox, repo, client = build_sandbox(stamped(with_herb(SAVED)))
    try:
        generated = os.path.join(repo, "Data", "Data_Harvested.lua")
        result = run_import(repo, client)
        check("an import with a herb on a mob succeeds", result.returncode == 0,
              result.stderr)

        text = open(generated, encoding="utf-8").read() if os.path.isfile(generated) else ""

        check("the herb is not written as a mob's drop",
              'name = "Peacebloom"' not in text, text)
        check("the mob's own drop still is", "chance = 62" in text, text)
    finally:
        shutil.rmtree(sandbox, ignore_errors=True)

    # -- A save from before the carryover was added ---------------------------
    #
    # Until the addon's first login after the SavedVariables fix, the saved
    # file holds one session and none of the history in the carryover.
    # Publishing it would drop that history out of the repository.
    sandbox, repo, client = build_sandbox(SAVED)
    try:
        data_file = os.path.join(repo, "Data", "Data_Harvested.lua")
        result = run_import(repo, client)

        check("a save without the carryover stamp is refused",
              result.returncode != 0, result.stdout)
        check("and says to log in once first",
              "Log in to WoW once" in (result.stderr + result.stdout),
              result.stderr)
        check("and writes nothing", not os.path.isfile(data_file))
    finally:
        shutil.rmtree(sandbox, ignore_errors=True)

    # -- Nothing harvested yet ------------------------------------------------
    sandbox, repo, client = build_sandbox(NO_HARVEST)
    try:
        data_file = os.path.join(repo, "Data", "Data_Harvested.lua")
        toc_file = os.path.join(repo, "Blackthornes_Farmer.toc")
        before_toc = open(toc_file, encoding="utf-8").read()

        result = run_import(repo, client)
        check("an empty harvest is refused", result.returncode != 0)
        check("and says what to do about it",
              "Loot some corpses" in (result.stderr + result.stdout),
              result.stderr)
        check("it writes no data file", not os.path.isfile(data_file))
        check("and does not touch the TOC",
              open(toc_file, encoding="utf-8").read() == before_toc)
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
