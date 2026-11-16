"""Run the addon's pure-logic tests outside WoW, against a real Lua 5.1 runtime.

    python tools/runtests.py                 every suite, a line each (what CI runs)
    python tools/runtests.py -q              only failures and the total
    python tools/runtests.py -q trash menu   only the suites whose name holds a word given

Every tools/test_*.lua is run, in name order. There is deliberately no list of
test files here: one used to exist, and because each new test appended to it,
any two branches adding tests collided on the same line. Four merges in one day
conflicted on nothing but that list. Discovering the files instead means a new
test is a new file and nothing else.

It also found two suites that were passing and being skipped -- test_persist
and test_serialize were never added to the list.

A suite fails by raising, which is what the assert and error calls in each file
do. All of them run regardless, so one failure does not hide the rest.
"""

import glob
import os
import sys

from lupa import lua51 as luamod

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def test_files():
    pattern = os.path.join(ROOT, "tools", "test_*.lua")
    return sorted(glob.glob(pattern), key=os.path.basename)


QUIET_TAIL = 12       # lines of a failed suite's own output shown with -q
QUIET_ERROR = 1500    # most letters of its error shown with -q


def main() -> int:
    args = sys.argv[1:]
    quiet = "-q" in args or "--quiet" in args
    words = [a for a in args if not a.startswith("-")]

    lua = luamod.LuaRuntime(unpack_returned_tuples=True)
    lua.execute("package.path = [[%s/?.lua;]] .. package.path" % ROOT.replace("\\", "/"))
    lua.execute("lfs_cwd = [[%s]]" % ROOT.replace("\\", "/"))

    scripts = test_files()
    if words:
        scripts = [p for p in scripts if any(w in os.path.basename(p) for w in words)]
    if not scripts:
        print("no test files found in tools/", file=sys.stderr)
        return 1

    failed = []

    # With -q a suite's own lines are kept aside and shown only if it fails,
    # so a passing run is two lines long.
    said = []
    if quiet:
        def keep(*parts):
            said.append("\t".join(str(part) for part in parts))
        lua.globals().print = keep

    for path in scripts:
        name = os.path.basename(path)
        del said[:]
        try:
            lua.execute("dofile([[%s]])" % path.replace("\\", "/"))
        except Exception as error:          # a Lua error, surfaced as LuaError
            failed.append(name)
            text = str(error)
            if quiet:
                for line in said[-QUIET_TAIL:]:
                    print("  " + line, file=sys.stderr)
                if len(text) > QUIET_ERROR:
                    text = text[:QUIET_ERROR] + " ..."
            print("\nFAIL -- %s\n%s" % (name, text), file=sys.stderr)

    print("\n%d suite(s) run, %d failure(s)" % (len(scripts), len(failed)))

    for name in failed:
        print("  failed: %s" % name)

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
