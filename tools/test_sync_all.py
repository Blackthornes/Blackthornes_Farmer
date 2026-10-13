"""Tests for tools/sync_all.ps1. Run: python tools/test_sync_all.py

Builds five pretend repos (a bare "GitHub" and a clone of each) in a temporary
folder, moves the bare ones on, and runs the script with -Root pointed there.
Needs PowerShell (pwsh, or powershell on Windows) and git; without PowerShell
it says so and passes, since the script cannot be run.
"""

import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "sync_all.ps1")
REPOS = {
    "Blackthornes_Farmer": "main",
    "Blackthornes_Tradeskills": "testing",
    "Blackthornes_Equipment": "main",
    "Blackthornes_Pets": "main",
    "Blackthornes_Butler": "main",
}

checks = 0
failures = 0


def expect(label, ok):
    global checks, failures
    checks += 1
    if not ok:
        failures += 1
        print(f"FAIL {label}")


def git(cwd, *args):
    env = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@example.invalid",
               GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@example.invalid")
    return subprocess.run(["git", *args], cwd=cwd, env=env, check=True,
                          capture_output=True, text=True).stdout.strip()


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)


def commit(work, files, message):
    for rel, text in files.items():
        if text is None:
            git(work, "rm", "-q", rel)
        else:
            write(os.path.join(work, rel), text)
            git(work, "add", rel)
    git(work, "commit", "-q", "-m", message)


def push_from_upstream(top, name, branch, files):
    """Commit to the pretend GitHub through a second clone."""
    up = os.path.join(top, "up", name)
    git(up, "pull", "-q", "--ff-only", "origin", branch)
    commit(up, files, "upstream change")
    git(up, "push", "-q", "origin", branch)


def build(top):
    root = os.path.join(top, "repos")
    os.makedirs(root)
    for name, branch in REPOS.items():
        bare = os.path.join(top, "remote", name + ".git")
        os.makedirs(bare)
        git(bare, "init", "-q", "--bare")
        up = os.path.join(top, "up", name)
        os.makedirs(up)
        git(up, "init", "-q", "-b", branch)
        git(up, "remote", "add", "origin", bare)
        commit(up, {name + ".toc": "## Title: x\n", "Core/Init.lua": "local a = 1\n"}, "first")
        git(up, "push", "-q", "origin", branch)
        git(top, "clone", "-q", "-b", branch, bare, os.path.join(root, name))
    return root


def run(shell, root):
    proc = subprocess.run([shell, "-NoProfile", "-File", SCRIPT, "-Root", root],
                          capture_output=True, text=True)
    return proc.returncode, proc.stdout


def line_for(out, name):
    for line in out.splitlines():
        if line.startswith(name + " "):
            return line
    return ""


def main():
    shell = shutil.which("pwsh") or shutil.which("powershell")
    if not shell or not shutil.which("git"):
        print("test_sync_all: no PowerShell or git here, skipped.")
        return 0

    top = tempfile.mkdtemp(prefix="sync_all_")
    try:
        root = build(top)

        # Nothing new anywhere.
        code, out = run(shell, root)
        expect("all current exits 0", code == 0)
        expect("all current summary", "0 updated, 5 already up to date, 0 skipped" in out)
        expect("nothing new", "Nothing new to load" in out)

        # Farmer: a change to an existing file only, so /reload.
        push_from_upstream(top, "Blackthornes_Farmer", "main", {"Core/Init.lua": "local a = 2\n"})
        # Tradeskills on testing: a new file, so a full restart.
        push_from_upstream(top, "Blackthornes_Tradeskills", "testing", {"UI/New.lua": "local b\n"})
        # Equipment: a .tga changed, so a full restart.
        push_from_upstream(top, "Blackthornes_Equipment", "main", {"Media/a.tga": "x"})
        eq = os.path.join(root, "Blackthornes_Equipment")
        # Pets: a file edited on this PC; it must be left alone.
        push_from_upstream(top, "Blackthornes_Pets", "main", {"Core/Init.lua": "local p = 3\n"})
        pets = os.path.join(root, "Blackthornes_Pets")
        write(os.path.join(pets, "Core/Init.lua"), "local mine = 1\n")
        pets_head = git(pets, "rev-parse", "HEAD")
        # Butler: on another branch; it must not be switched.
        push_from_upstream(top, "Blackthornes_Butler", "main", {"Core/Init.lua": "local q = 4\n"})
        butler = os.path.join(root, "Blackthornes_Butler")
        git(butler, "checkout", "-q", "-b", "my-test")

        code, out = run(shell, root)
        print(out)
        expect("skips make exit 1", code == 1)
        farmer = line_for(out, "Blackthornes_Farmer")
        expect("farmer updated", "updated" in farmer and "/reload is enough" in farmer)
        ts = line_for(out, "Blackthornes_Tradeskills")
        expect("tradeskills on testing", "(testing)" in ts and "full restart" in ts)
        expect("tga needs restart", "full restart" in line_for(out, "Blackthornes_Equipment"))
        expect("equipment moved", git(eq, "rev-parse", "HEAD") == git(eq, "rev-parse", "origin/main"))
        expect("pets skipped", "changed on this PC" in line_for(out, "Blackthornes_Pets"))
        expect("pets untouched", git(pets, "rev-parse", "HEAD") == pets_head)
        with open(os.path.join(pets, "Core/Init.lua")) as f:
            expect("pets edit kept", f.read() == "local mine = 1\n")
        expect("butler skipped", "on my-test, not main" in line_for(out, "Blackthornes_Butler"))
        expect("butler not switched", git(butler, "rev-parse", "--abbrev-ref", "HEAD") == "my-test")
        expect("summary", "3 updated, 0 already up to date, 2 skipped" in out)
        expect("summary restart", "Restart the game fully" in out)

        # Farmer split from GitHub: a local commit and a new upstream one.
        fa = os.path.join(root, "Blackthornes_Farmer")
        commit(fa, {"Core/Local.lua": "local l\n"}, "local only")
        push_from_upstream(top, "Blackthornes_Farmer", "main", {"Core/Init.lua": "local a = 9\n"})
        before = git(fa, "rev-parse", "HEAD")
        code, out = run(shell, root)
        expect("diverged skipped", "cannot fast-forward" in line_for(out, "Blackthornes_Farmer"))
        expect("diverged untouched", git(fa, "rev-parse", "HEAD") == before)

        # A deleted file also needs a restart; a missing repo is skipped.
        git(fa, "reset", "-q", "--hard", "origin/main")
        push_from_upstream(top, "Blackthornes_Farmer", "main", {"Core/Init.lua": None})
        shutil.rmtree(os.path.join(root, "Blackthornes_Pets"))
        code, out = run(shell, root)
        expect("delete needs restart", "full restart" in line_for(out, "Blackthornes_Farmer"))
        expect("missing repo skipped", "no git repo" in line_for(out, "Blackthornes_Pets"))
        expect("missing exits 1", code == 1)
    finally:
        shutil.rmtree(top, ignore_errors=True)

    print(f"test_sync_all: {checks - failures}/{checks} passed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
