"""Proof that tools/backlog.py holds its rules. Run: python3 -m unittest tests/test_backlog.py

Each test builds a throwaway git repo with a copy of the tool, so nothing touches this repo's backlog.
"""
from __future__ import annotations

import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

TOOL = Path(__file__).resolve().parents[1] / "tools" / "backlog.py"


def sh(cwd: Path, *args: str, env: dict | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(list(args), cwd=cwd, capture_output=True, text=True, env=env)


class Sandbox:
    def __init__(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="backlog-test-"))
        self.repo = self.tmp / "repo"
        (self.repo / "tools").mkdir(parents=True)
        shutil.copy(TOOL, self.repo / "tools" / "backlog.py")
        (self.repo / "evidence.txt").write_text("a measured result\n")
        sh(self.repo, "git", "init", "-q", "-b", "main")
        sh(self.repo, "git", "add", ".")
        sh(self.repo, "git", "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "init")
        assert self.run("init").returncode == 0

    def run(self, *args: str, cwd: Path | None = None, env: dict | None = None) -> subprocess.CompletedProcess:
        root = cwd or self.repo
        return sh(root, sys.executable, str(root / "tools" / "backlog.py"), *args, env=env)

    def files(self, folder: str) -> list[Path]:
        return sorted((self.repo / "backlog" / folder).glob("*.md"))

    def close(self):
        shutil.rmtree(self.tmp, ignore_errors=True)


class BacklogTest(unittest.TestCase):
    def setUp(self):
        self.sb = Sandbox()

    def tearDown(self):
        self.sb.close()

    def new(self, title: str = "a task") -> str:
        r = self.sb.run("new", title)
        self.assertEqual(r.returncode, 0, r.stderr)
        return r.stdout.split()[0]

    def test_parallel_new_mints_unique_ids(self):
        with ThreadPoolExecutor(8) as pool:
            results = list(pool.map(lambda i: self.sb.run("new", f"task {i}"), range(8)))
        ids = [r.stdout.split()[0] for r in results]
        self.assertEqual(len(set(ids)), 8, ids)

    def test_parallel_claims_have_exactly_one_winner(self):
        task = self.new()
        with ThreadPoolExecutor(8) as pool:
            results = list(pool.map(
                lambda i: self.sb.run("claim", task, "--next", "start", "--agent", f"agent-{i}"), range(8)))
        self.assertEqual(sum(r.returncode == 0 for r in results), 1, [r.stderr for r in results])

    def test_claimed_task_refuses_a_second_agent_and_expiry_frees_it(self):
        task = self.new()
        self.assertEqual(self.sb.run("claim", task, "--next", "x", "--agent", "a", "--ttl-hours", "0").returncode, 0)
        self.assertEqual(self.sb.run("claim", task, "--next", "y", "--agent", "b").returncode, 0)
        r = self.sb.run("handoff", task, "--state", "s.", "--next", "n", "--agent", "a")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("claimed by b", r.stderr)

    def test_done_refuses_missing_or_unresolvable_evidence(self):
        task = self.new()
        self.sb.run("claim", task, "--next", "x", "--agent", "a")
        for evidence in ([], ["no/such/file.md"], ["deadbeefdeadbeef"]):
            r = self.sb.run("done", task, "--summary", "s", "--agent", "a", *(["--evidence", *evidence] if evidence else []))
            self.assertEqual(r.returncode, 2, (evidence, r.stdout))
        self.assertEqual(len(self.sb.files("tasks")), 1)

    def test_done_with_evidence_archives_and_passes_check(self):
        task = self.new()
        self.sb.run("claim", task, "--next", "x", "--agent", "a")
        commit = sh(self.sb.repo, "git", "rev-parse", "HEAD").stdout.strip()
        r = self.sb.run("done", task, "--evidence", "evidence.txt", commit, "https://example.com/run/1",
                        "--summary", "it works", "--agent", "a")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(len(self.sb.files("tasks")), 0)
        self.assertEqual(len(self.sb.files("completed")), 1)
        self.assertEqual(self.sb.run("check").returncode, 0, self.sb.run("check").stdout)

    def test_check_catches_hand_edits(self):
        task = self.new()
        path = self.sb.files("tasks")[0]
        path.write_text(path.read_text().replace("status: To Do", "status: In Progress"))
        r = self.sb.run("check")
        self.assertEqual(r.returncode, 1)
        self.assertIn("empty Handoff", r.stdout)
        path.write_text(path.read_text().replace("status: In Progress", "status: Doing"))
        self.assertIn("is not one of", self.sb.run("check").stdout)

    def test_decision_needs_resolving_evidence_unless_directive(self):
        args = ["decide", "Use X over Y", "--context", "c", "--options", "X, Y", "--decision", "X"]
        self.assertEqual(self.sb.run(*args).returncode, 2)
        self.assertEqual(self.sb.run(*args, "--evidence", "evidence.txt").returncode, 0)
        self.assertEqual(self.sb.run(*args, "--origin", "directive").returncode, 0)
        decision = self.sb.files("decisions")[0]
        decision.write_text(decision.read_text().replace("`evidence.txt`", "`gone.txt`"))
        self.assertIn("origin 'evidence' needs", self.sb.run("check").stdout)

    def test_worktrees_share_id_space_and_claims(self):
        wt = self.sb.tmp / "wt2"
        sh(self.sb.repo, "git", "worktree", "add", "-q", "-b", "other", str(wt))
        first = self.new()
        second = self.sb.run("new", "from the other worktree", cwd=wt).stdout.split()[0]
        self.assertNotEqual(first, second)
        self.assertEqual(self.sb.run("claim", first, "--next", "x", "--agent", "a").returncode, 0)
        # The task file is not in wt2's tree, but the claim lives in the shared git dir.
        self.assertTrue(any((Path(sh(wt, "git", "rev-parse", "--path-format=absolute", "--git-common-dir").stdout.strip())
                             / "backlog-state" / "claims").glob(f"{first}.json")))

    def test_brief_shows_active_work_and_last_handoff(self):
        task = self.new("deck build")
        self.sb.run("claim", task, "--next", "render slide 3", "--agent", "a")
        self.sb.run("handoff", task, "--state", "slides 1-2 built.", "--next", "render slide 3", "--agent", "a")
        r = self.sb.run("brief")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("deck build", r.stdout)
        self.assertIn("slides 1-2 built.", r.stdout)

    def test_titles_with_colons_round_trip(self):
        self.new("Exp 3: classify patterns")
        self.assertIn("title: \"Exp 3: classify patterns\"", self.sb.files("tasks")[0].read_text())
        self.assertIn("Exp 3: classify patterns", self.sb.run("index").stdout)
        self.assertEqual(self.sb.run("check").returncode, 0)

    def test_github_source_imports_open_issues_once(self):
        bin_dir = self.sb.tmp / "bin"
        bin_dir.mkdir()
        fake = bin_dir / "gh"
        issues = [{"number": 1, "title": "open one", "body": "b", "labels": [{"name": "bug"}],
                   "url": "https://github.com/o/r/issues/1", "state": "OPEN"},
                  {"number": 2, "title": "closed one", "body": "", "labels": [],
                   "url": "https://github.com/o/r/issues/2", "state": "CLOSED"}]
        fake.write_text(f"#!/bin/sh\ncat <<'EOF'\n{json.dumps(issues)}\nEOF\n")
        fake.chmod(fake.stat().st_mode | stat.S_IEXEC)
        (self.sb.repo / "backlog").mkdir(exist_ok=True)
        (self.sb.repo / "backlog" / "sources.json").write_text(json.dumps([{"type": "github", "repo": "o/r"}]))
        env = dict(os.environ, PATH=f"{bin_dir}{os.pathsep}{os.environ['PATH']}")
        self.assertEqual(self.sb.run("sync", env=env).returncode, 0)
        self.assertEqual(self.sb.run("sync", env=env).returncode, 0)
        files = self.sb.files("tasks")
        self.assertEqual(len(files), 1)
        self.assertIn("source: https://github.com/o/r/issues/1", files[0].read_text())

    def test_init_is_idempotent_and_never_touches_text_outside_its_block(self):
        agents = self.sb.repo / "AGENTS.md"
        agents.write_text("# Human intro\n\nOur own words.\n\n<!-- other-tool:start -->\nx\n<!-- other-tool:end -->\n"
                          + agents.read_text().split("# ", 1)[0])
        hook = self.sb.repo / ".githooks" / "pre-commit"
        hook.write_text("#!/bin/sh\necho existing hook\nexec true\n")
        for _ in range(2):
            self.assertEqual(self.sb.run("init").returncode, 0)
        text = agents.read_text()
        self.assertEqual(text.count("<!-- backlog:start -->"), 1)
        self.assertIn("Our own words.", text)
        self.assertIn("<!-- other-tool:start -->\nx\n<!-- other-tool:end -->", text)
        lines = hook.read_text().splitlines()
        self.assertEqual(sum("tools/backlog.py check" in line for line in lines), 1)
        self.assertLess(next(i for i, l in enumerate(lines) if "backlog.py check" in l), lines.index("exec true"))
        settings = json.loads((self.sb.repo / ".claude" / "settings.json").read_text())
        self.assertEqual(len(settings["hooks"]["SessionStart"]), 1)
        self.assertEqual((self.sb.repo / ".gitignore").read_text().count("backlog/INDEX.md"), 1)
        self.assertEqual((self.sb.repo / "CLAUDE.md").read_text(), "@AGENTS.md\n")

    def test_check_fails_when_the_block_is_hand_edited_but_not_when_outside_text_changes(self):
        agents = self.sb.repo / "AGENTS.md"
        agents.write_text("Anything we like.\n" + agents.read_text())
        self.assertEqual(self.sb.run("check").returncode, 0)
        agents.write_text(agents.read_text().replace("Claim a task", "Grab a task"))
        r = self.sb.run("check")
        self.assertEqual(r.returncode, 1)
        self.assertIn("hand-edited", r.stdout)

    def test_existing_adr_folder_is_listed_read_only(self):
        adr = self.sb.repo / "docs" / "adr"
        adr.mkdir(parents=True)
        (adr / "0000-template.md").write_text("# Template\n")
        (adr / "0004-let-the-window-become-key.md").write_text("# 4. Let the window become key\n\nStatus: Accepted\n")
        (self.sb.repo / "backlog" / "sources.json").write_text(json.dumps([{"type": "adr", "path": "docs/adr"}]))
        out = self.sb.run("index").stdout
        self.assertIn("4. Let the window become key · Accepted", out)
        self.assertNotIn("Template", out)
        self.assertEqual(self.sb.run("sync").returncode, 0)

    def test_init_never_bypasses_active_local_hooks(self):
        sb = Sandbox.__new__(Sandbox)
        sb.tmp = Path(tempfile.mkdtemp(prefix="backlog-test-"))
        sb.repo = sb.tmp / "repo"
        (sb.repo / "tools").mkdir(parents=True)
        shutil.copy(TOOL, sb.repo / "tools" / "backlog.py")
        sh(sb.repo, "git", "init", "-q", "-b", "main")
        hook = sb.repo / ".git" / "hooks" / "pre-commit"
        hook.write_text("#!/bin/sh\nexit 0\n")
        try:
            r = sb.run("init")
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertIn("bypass active hooks", r.stdout)
            self.assertEqual(sh(sb.repo, "git", "config", "--get", "core.hooksPath").stdout.strip(), "")
        finally:
            sb.close()


if __name__ == "__main__":
    unittest.main()
