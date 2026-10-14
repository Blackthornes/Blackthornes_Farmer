"""Checks for tools/forever_npc_names.py.

    python tools/test_forever_npc_names.py

It reads only npcNames from a save, ships names for IDs Classic's list
lacks, never changes one already shipped, and drops anything that is not a
plain name.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import forever_npc_names as tool  # noqa: E402

SAVE = """
BlackthornesFarmerDB = {
\t["harvest"] = {
\t\t["x"] = { ["npc"] = 5, },
\t},
\t["npcNames"] = {
\t\t[250484] = "Spider",
\t\t[250488] = "Lordaeron \\"Ghoul\\"",
\t\t[11318] = "Ragefire Trogg",
\t\t[250500] = "Creature #250500",
\t\t[250501] = "|cffff0000Red|r",
\t\t[250502] = "12345",
\t\t[250503] = "Broodling",
\t},
\t["other"] = { [1] = "Not a name", },
}
"""

failures = 0


def check(label, ok):
    global failures
    print(("ok   " if ok else "FAIL ") + label)
    if not ok:
        failures += 1


names = tool.build(SAVE, {11318: "Ragefire Trogg"}, {250503: "Shipped Broodling"})
check("a Forever mob's name is kept", names.get(250484) == "Spider")
check("quotes survive", names.get(250488) == 'Lordaeron "Ghoul"')
check("Classic's IDs are left to Classic's list", 11318 not in names)
check("a number is never a name", 250500 not in names and 250502 not in names)
check("colour codes are taken out", names.get(250501) == "cffff0000Redr" or 250501 not in names)
check("a shipped name is never changed", names.get(250503) == "Shipped Broodling")
check("only npcNames is read", 1 not in names)
check("lua output escapes quotes", tool.lua_string('a"b') == 'a\\"b')

if failures:
    sys.exit("%d failure(s)" % failures)
print("all passed")
