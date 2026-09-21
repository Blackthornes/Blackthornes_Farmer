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

# The shape the client actually leaves behind after a login that looted
# nothing: the table is there, and empty. Not the same as no table, and it
# contributes exactly as much.
EMPTY_HARVEST = 'BlackthornesFarmerDB = { ["harvest"] = {} }\n'

# A later session at the same spot, plus a new one. The overlapping mob has a
# wider level band and coins in its loot, so one file exercises accumulation,
# the widening, and the coin filter together.
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

    # The store is deliberately left behind. It is the running total of every
    # real harvest, and a sandbox that inherited it would be testing against
    # Trent's data instead of its own.
    shutil.copytree(ROOT, repo,
                    ignore=shutil.ignore_patterns(".git", "Harvest_Store.lua"))

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


def store_records(path):
    """The store's records, without the fingerprint of the file that fed them.

    The fingerprint changes whenever the client rewrites SavedVariables, which
    it does at every logout whether or not anything was looted. The records are
    the part that must not change.
    """
    text = open(path, encoding="utf-8").read()
    return text.split("BlackthornesFarmerHarvestSource")[0]


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
        #
        # Each run adds the session to a running total, so a second run over an
        # unchanged file must add nothing. Double-clicking the desktop shortcut
        # twice is not a reason for every number in the repository to double.
        again = run_import(repo, client)
        check("a second import succeeds", again.returncode == 0, again.stderr)
        check("and recognises it as the same logout",
              "already imported" in again.stdout, again.stdout)

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
    #
    # A checkout already carries a generated data file and a TOC line for it,
    # so the thing to check is that a refused import leaves both exactly as
    # they were -- not that neither exists.
    sandbox, repo, client = build_sandbox(NO_HARVEST)
    try:
        data_file = os.path.join(repo, "Data", "Data_Harvested.lua")
        toc_file = os.path.join(repo, "Blackthornes_Farmer.toc")

        before_data = (open(data_file, encoding="utf-8").read()
                       if os.path.isfile(data_file) else None)
        before_toc = open(toc_file, encoding="utf-8").read()

        result = run_import(repo, client)
        check("an empty harvest is refused", result.returncode != 0)
        check("and says what to do about it",
              "Loot some corpses" in (result.stderr + result.stdout),
              result.stderr)

        after_data = (open(data_file, encoding="utf-8").read()
                      if os.path.isfile(data_file) else None)
        check("it leaves the data file alone", after_data == before_data)
        check("it starts no store",
              not os.path.isfile(os.path.join(repo, "Data", "Harvest_Store.lua")))
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

    # -- The store keeps history across sessions ------------------------------
    #
    # This is the bug that cost seventy-three corpses of real harvest on
    # 2026-09-21. The client writes saved variables at logout but is not
    # reported to read them back at login, so the addon starts empty every
    # session and its saved file describes only the last session that looted
    # anything. The running total therefore has to live here, in a file both
    # sides can read, and a thin session must never replace a full history.

    sandbox, repo, client = build_sandbox(SAVED)
    store = os.path.join(repo, "Data", "Harvest_Store.lua")
    generated = os.path.join(repo, "Data", "Data_Harvested.lua")

    try:
        first = run_import(repo, client)
        check("the first import succeeds", first.returncode == 0, first.stderr)
        check("it starts a store", os.path.isfile(store))
        check("and says so", "starting a new harvest store" in first.stdout,
              first.stdout)
        check("55 corpses are recorded", "55 corpses" in first.stdout,
              first.stdout)

        kept = store_records(store)
        after_first = open(generated, encoding="utf-8").read()

        # A login that looted nothing. Before the fix this wrote an empty
        # table over everything above.
        write_saved(client, EMPTY_HARVEST)
        quiet = run_import(repo, client)

        check("a session that looted nothing still succeeds",
              quiet.returncode == 0, quiet.stderr)
        check("and reports that it added nothing",
              "nothing new" in quiet.stdout, quiet.stdout)
        check("THE HISTORY SURVIVES AN EMPTY SESSION",
              store_records(store) == kept)
        check("and the generated file is unchanged by it",
              open(generated, encoding="utf-8").read() == after_first)

        # A real second session: one spot seen again, one new.
        write_saved(client, LATER)
        more = run_import(repo, client)

        check("a later session succeeds", more.returncode == 0, more.stderr)
        check("it reports the new spot", "1 spot(s) added" in more.stdout,
              more.stdout)
        check("corpses accumulate across sessions", "71 corpses" in more.stdout,
              more.stdout)

        # 47 + 10 at the Sepulcher, and Wool Cloth off 29 + 5 of them.
        grown = open(generated, encoding="utf-8").read()
        check("the shared spot adds up", "-- 34 of 57 corpses" in grown, grown)
        check("the new spot arrives", "Wolf Meat" in grown)
        check("the level band widens to cover both",
              "minLevel = 19, maxLevel = 24" in grown, grown)

        # -- Coins are not drops ------------------------------------------------
        check("coins never reach the data file",
              "14 Copper" not in grown, grown)
        check("nor the store", "14 Copper" not in store_records(store))

        grown_store = store_records(store)

        # -- If the client turns out to read SavedVariables back ----------------
        #
        # Adding each logout to a running total is only correct while the addon
        # starts every login empty. The addon stamps the save with how much it
        # restored, and a non-zero stamp has to stop the import rather than
        # count the same corpses twice.
        write_saved(client, LATER.replace(
            'BlackthornesFarmerDB = {',
            'BlackthornesFarmerDB = {\n\t["harvestRestored"] = 2,'))

        cumulative = run_import(repo, client)

        check("a client that reads its saved data back is refused",
              cumulative.returncode != 0, cumulative.stdout)
        check("and says why",
              "count the same corpses twice"
              in (cumulative.stdout + cumulative.stderr), cumulative.stderr)
        check("and changes nothing", store_records(store) == grown_store)
        check("leaving the data file alone",
              open(generated, encoding="utf-8").read() == grown)

        # -- Rebuilding the store from the data file ----------------------------
        #
        # The store is the file that must not be lost, so it matters that it
        # can be put back. Everything a published rate is made of is in the
        # generated file already: the two numbers in each "N of M corpses"
        # comment are exactly the numerator and denominator.

        os.remove(store)
        recovered = subprocess.run(
            [sys.executable, os.path.join(repo, "tools", "harvest_recover.py")],
            capture_output=True, text=True, cwd=repo)

        check("recovery runs", recovered.returncode == 0, recovered.stderr)
        check("it puts the store back", os.path.isfile(store))
        check("with every corpse", "71 corpses" in recovered.stdout,
              recovered.stdout)

        write_saved(client, EMPTY_HARVEST)
        after = run_import(repo, client)

        check("the recovered store imports", after.returncode == 0, after.stderr)
        check("and regenerates the same data file, byte for byte",
              open(generated, encoding="utf-8").read() == grown)

        # It refuses to trample a store that is already there.
        refused = subprocess.run(
            [sys.executable, os.path.join(repo, "tools", "harvest_recover.py")],
            capture_output=True, text=True, cwd=repo)

        check("recovery will not overwrite an existing store",
              refused.returncode != 0)
        check("and says how to override it",
              "--force" in (refused.stdout + refused.stderr), refused.stderr)
    finally:
        shutil.rmtree(sandbox, ignore_errors=True)

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
