"""backlog - the repo's task backlog, decision records and handoff trail (see backlog/README.md).

    python3 tools/backlog.py init                                install: dirs, README, AGENTS.md block, hooks (idempotent)
    python3 tools/backlog.py brief                               session start: index + active + ready + latest decisions
    python3 tools/backlog.py index                               rebuild backlog/INDEX.md (git-ignored) and print it
    python3 tools/backlog.py check [--quiet]                     validate every file; exit 1 on any violation
    python3 tools/backlog.py new "<title>" [--description D] [--ac A]... [--label L]... [--dep task-N]...
    python3 tools/backlog.py claim <task-N> --next "<first step>" [--agent A] [--ttl-hours H]
    python3 tools/backlog.py handoff <task-N> --state "<where it is>" --next "<next step>" [--agent A]
    python3 tools/backlog.py release <task-N> [--agent A]
    python3 tools/backlog.py done <task-N> --evidence REF... --summary "<what changed>" [--agent A]
    python3 tools/backlog.py cancel <task-N> --reason "<why>"
    python3 tools/backlog.py decide "<title>" --context C --options O --decision D --evidence REF...
                                    [--origin evidence|directive|convention|constraint] [--task task-N]...
    python3 tools/backlog.py sync                                pull optional sources (backlog/sources.json) into tasks

The tool owns one marked block in AGENTS.md (<!-- backlog:start --> ... <!-- backlog:end -->) and never touches
the text around it. Files are plain markdown with Backlog.md-compatible front matter, so that CLI and board can read them too.
Claims and id reservations live in the git common dir, shared by every worktree of this clone and never
committed: two agents cannot claim one task, and two worktrees cannot mint the same id.
An evidence REF is a repo path, an http(s) URL or a git commit; each one must resolve.
Stdlib only.
"""
from __future__ import annotations

import argparse
import getpass
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BACKLOG = ROOT / "backlog"
DIRS = {"tasks": BACKLOG / "tasks", "completed": BACKLOG / "completed",
        "archive": BACKLOG / "archive", "decisions": BACKLOG / "decisions"}
INDEX = BACKLOG / "INDEX.md"
AGENTS = ROOT / "AGENTS.md"
SOURCES = BACKLOG / "sources.json"

STATUSES = {"To Do", "In Progress", "Done", "Cancelled"}
ORIGINS = {"evidence", "directive", "convention", "constraint"}
TASK_KEYS = ["id", "title", "status", "assignee", "created_date", "updated_date", "labels", "dependencies"]
DECISION_KEYS = ["id", "title", "date", "status", "origin"]
ID_RE = re.compile(r"^(task|decision)-(\d+)\b")
DEFAULT_TTL_HOURS = 12
BLOCK = "backlog"
BLOCK_BODY = """<!-- Managed by tools/backlog.py init. Text outside this block is yours and is never touched. -->
## Live work and decisions

Run `python3 tools/backlog.py brief` first: work in progress with its last handoff, ready tasks and the latest
decisions. Claude Code runs it at session start.

- Claim a task before you change anything for it. Hand off before you stop, and when your context runs low.
- Close a task with evidence (a repo path, URL or commit). Record every choice between methods as a decision.
- Full rules: `backlog/README.md`."""
SETTINGS_HOOK = 'python3 "$CLAUDE_PROJECT_DIR/tools/backlog.py" brief 2>/dev/null || true'
PRE_COMMIT_LINE = "[ -f tools/backlog.py ] && { python3 tools/backlog.py check --quiet || exit 1; }"
GITIGNORE_LINES = ["# backlog: generated on demand; committing it would conflict between agents.",
                   "backlog/INDEX.md", ".backlog-state/"]
README = """# Backlog

Where work, decisions and handoffs live, so any agent can pick up where another stopped.

```
backlog/
  INDEX.md          generated on demand, git-ignored: in progress, ready, decisions, recently done
  tasks/            open work (To Do, In Progress), one file per task
  completed/        Done tasks, each with its evidence and final summary
  archive/          Cancelled tasks
  decisions/        why we chose one method over another, with the evidence behind it
  sources.json      optional: GitHub issues imported as tasks, existing ADR folders listed in the index
```

Every file is markdown with Backlog.md-compatible front matter, so the Backlog.md CLI and board can read it. Nothing
requires them. All changes go through `python3 tools/backlog.py` (stdlib only). The tool owns one marked block in
`AGENTS.md` and never touches the text around it.

## Lifecycle

| Step | Command | What the tool enforces |
|---|---|---|
| Start a session | `brief` | Prints the index. Runs on Claude Code session start. |
| Add work | `new "<title>" --ac "<criterion>"` | An id no other worktree or branch holds |
| Take work | `claim task-N --next "<first step>"` | One owner per task across every worktree on this machine. Claims expire after 12 hours. |
| Leave a trace | `handoff task-N --state "<where it is>" --next "<next step>"` | Renews the claim |
| Finish | `done task-N --evidence <path or URL or commit>... --summary "..."` | Refuses without a handoff trail, a summary and evidence that resolves. Moves the task to `completed/`. |
| Drop | `cancel task-N --reason "..."` | Moves the task to `archive/` |
| Record a choice | `decide "<title>" --context --options --decision --evidence` | Evidence must resolve unless `--origin` is directive, convention or constraint |
| Import | `sync` | Opens a task for each new open issue. Lists tasks whose issue was closed. |

## Rules for agents

1. Run `brief` first. Claim a task before you change anything for it.
2. Write a handoff before you stop, before a long wait, and when your context is running low. The next agent reads only
   that trail.
3. When you choose between two methods, record a decision and cite the test, run folder, ledger row or commit that
   backs it. "Why did we do X?" is answered from `decisions/`, never from memory.
4. Work in your own worktree and branch. Never edit `INDEX.md`; it is rebuilt from the files.

`check` validates the format of every file, the content each status requires and the AGENTS.md block. It runs on every
commit through `.githooks/pre-commit` and in CI. The tests in `tests/test_backlog.py` prove that two agents cannot claim
one task, that a task cannot close without resolving evidence, and that worktrees never mint the same id.
"""


class Fail(Exception):
    """A refusal written for the next agent: say what is wrong and the command that fixes it."""


# ---------------------------------------------------------------- small helpers
def now() -> datetime:
    return datetime.now(timezone.utc)


def stamp(t: datetime | None = None) -> str:
    return (t or now()).strftime("%Y-%m-%d %H:%MZ")


def today() -> str:
    return now().strftime("%Y-%m-%d")


def git(*args: str) -> str:
    r = subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else ""


def state_dir() -> Path:
    common = git("rev-parse", "--path-format=absolute", "--git-common-dir")
    base = Path(common) if common else ROOT / ".backlog-state"
    return base / "backlog-state"


def set_hooks_path() -> str:
    """Point git at .githooks unless that would silently bypass hooks already active in the clone."""
    current = git("config", "--get", "core.hooksPath")
    if current:
        return "" if current.rstrip("/") == ".githooks" else \
            f"backlog: core.hooksPath is {current}; add this line to its pre-commit: {PRE_COMMIT_LINE}"
    common = git("rev-parse", "--path-format=absolute", "--git-common-dir")
    active = [h.name for h in Path(common, "hooks").glob("*") if not h.name.endswith(".sample")] if common else []
    if active:
        return f"backlog: left core.hooksPath unset, since it would bypass active hooks ({', '.join(active)})."
    git("config", "core.hooksPath", ".githooks")
    return "backlog: set core.hooksPath=.githooks so commits run `backlog.py check`."


def default_agent() -> str:
    return os.environ.get("BACKLOG_AGENT") or f"{getpass.getuser()}@{ROOT.name}"


def slug(title: str) -> str:
    words = re.sub(r"[^a-z0-9]+", " ", title.lower()).split()
    kept = [w for i, w in enumerate(words) if len("-".join(words[:i + 1])) <= 60]
    return "-".join(kept or words[:1])[:60] or "untitled"


def write_atomic(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    tmp.write_text(text, encoding="utf-8")
    os.replace(tmp, path)


def block_re(name: str) -> re.Pattern:
    return re.compile(rf"^<!-- {re.escape(name)}:start -->[ \t]*\n(.*?)^<!-- {re.escape(name)}:end -->[ \t]*$", re.S | re.M)


def get_block(text: str, name: str) -> str | None:
    found = block_re(name).findall(text)
    return found[0].rstrip("\n") if len(found) == 1 else None


def upsert_block(path: Path, name: str, body: str) -> None:
    """Replace this tool's marked block in place, or append it once. Text outside the block is never touched."""
    text = path.read_text(encoding="utf-8") if path.exists() else ""
    block = f"<!-- {name}:start -->\n{body.strip()}\n<!-- {name}:end -->"
    text = block_re(name).sub(lambda _: block, text, count=1) if get_block(text, name) is not None \
        else (text.rstrip("\n") + "\n\n" if text.strip() else "") + block + "\n"
    write_atomic(path, text)


# ---------------------------------------------------------------- the file format
def parse_value(raw: str):
    raw = raw.strip()
    if raw.startswith("[") and raw.endswith("]"):
        return [v.strip().strip("'\"") for v in raw[1:-1].split(",") if v.strip()]
    if raw.startswith('"') and raw.endswith('"'):
        return json.loads(raw)
    return raw.strip("'")


def render_value(v) -> str:
    if isinstance(v, list):
        return "[" + ", ".join(v) + "]"
    return json.dumps(v, ensure_ascii=False) if re.search(r":(\s|$)|\s#|^[\[\]{}#&*!|>'\"%@`]|^\s|\s$", str(v)) else str(v)


class Doc:
    """One task or decision: front matter + ordered '## ' sections."""

    def __init__(self, path: Path, meta: dict, sections: dict[str, str]):
        self.path, self.meta, self.sections = path, meta, sections

    @classmethod
    def load(cls, path: Path) -> "Doc":
        text = path.read_text(encoding="utf-8")
        m = re.match(r"^---\n(.*?)\n---\n?(.*)$", text, re.S)
        if not m:
            return cls(path, {}, {"_body": text})
        meta = dict((k.strip(), parse_value(v)) for k, v in
                    (line.split(":", 1) for line in m.group(1).splitlines() if ":" in line))
        parts = re.split(r"^## +(.+?)\s*$", m.group(2), flags=re.M)
        sections = {"_preamble": parts[0].strip()} if parts[0].strip() else {}
        sections.update((parts[i].strip(), parts[i + 1].strip()) for i in range(1, len(parts) - 1, 2))
        return cls(path, meta, sections)

    def save(self) -> None:
        front = "\n".join(f"{k}: {render_value(v)}" for k, v in self.meta.items())
        body = "\n\n".join(f"## {name}\n\n{text}".rstrip() for name, text in self.sections.items()
                           if not name.startswith("_"))
        write_atomic(self.path, f"---\n{front}\n---\n\n{body}\n")

    @property
    def id(self) -> str:
        return str(self.meta.get("id", ""))

    def section(self, name: str) -> str:
        return self.sections.get(name, "").strip()

    def append(self, name: str, line: str) -> None:
        self.sections[name] = (self.section(name) + "\n" + line).strip()


def docs(*kinds: str) -> list[Doc]:
    return [Doc.load(p) for kind in kinds for p in sorted(DIRS[kind].glob("*.md"))]


def id_num(doc_id: str) -> int:
    m = ID_RE.match(doc_id)
    return int(m.group(2)) if m else 0


def find(doc_id: str) -> Doc:
    match = next((d for d in docs("tasks", "completed", "archive", "decisions") if d.id == doc_id), None)
    if not match:
        raise Fail(f"{doc_id} not found under backlog/. List them with: python3 tools/backlog.py index")
    return match


# ---------------------------------------------------------------- ids: unique across worktrees and branches
def known_ids(kind: str) -> set[int]:
    names: list[str] = []
    worktrees = [line[9:] for line in git("worktree", "list", "--porcelain").splitlines() if line.startswith("worktree ")]
    for wt in worktrees or [str(ROOT)]:
        names += [p.name for p in Path(wt, "backlog").glob("*/*.md")]
    for ref in git("for-each-ref", "--format=%(refname)", "refs/heads", "refs/remotes").splitlines():
        names += [Path(p).name for p in git("ls-tree", "-r", "--name-only", ref, "--", "backlog/").splitlines()]
    reserved = state_dir() / "ids"
    names += [p.name for p in reserved.glob(f"{kind}-*")] if reserved.exists() else []
    return {int(m.group(2)) for m in map(ID_RE.match, names) if m and m.group(1) == kind}


def next_id(kind: str) -> str:
    reserved = state_dir() / "ids"
    reserved.mkdir(parents=True, exist_ok=True)
    n = max(known_ids(kind), default=0) + 1
    while True:
        try:
            os.close(os.open(reserved / f"{kind}-{n}", os.O_CREAT | os.O_EXCL | os.O_WRONLY))
            return f"{kind}-{n}"
        except FileExistsError:
            n += 1


# ---------------------------------------------------------------- claims: one owner per task, atomic
def claim_path(task_id: str) -> Path:
    return state_dir() / "claims" / f"{task_id}.json"


def read_claim(task_id: str) -> dict | None:
    try:
        return json.loads(claim_path(task_id).read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError):
        return None


def expired(claim: dict) -> bool:
    return datetime.fromisoformat(claim["expires_at"]) <= now()


def write_claim(task_id: str, agent: str, ttl_hours: float, exclusive: bool) -> dict:
    claim = {"task": task_id, "agent": agent, "worktree": str(ROOT), "branch": git("branch", "--show-current"),
             "claimed_at": now().isoformat(), "expires_at": (now() + timedelta(hours=ttl_hours)).isoformat()}
    path = claim_path(task_id)
    path.parent.mkdir(parents=True, exist_ok=True)
    if not exclusive:
        write_atomic(path, json.dumps(claim, indent=2))
        return claim
    fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(claim, f, indent=2)
    return claim


def refuse_if_foreign(task_id: str, agent: str) -> dict | None:
    claim = read_claim(task_id)
    if claim and claim["agent"] != agent and not expired(claim):
        raise Fail(f"{task_id} is claimed by {claim['agent']} (worktree {claim['worktree']}, branch "
                   f"{claim['branch']}) until {claim['expires_at']}. Pick another task, or wait for expiry.")
    return claim


# ---------------------------------------------------------------- evidence: every reference must resolve
def ref_ok(ref: str) -> bool:
    ref = ref.strip().strip("`")
    if re.match(r"^https?://\S+$", ref):
        return True
    if re.fullmatch(r"[0-9a-f]{7,40}", ref) and git("cat-file", "-t", ref) == "commit":
        return True
    path = ref.split("#", 1)[0]
    return bool(path) and (ROOT / path).exists()


def refs_in(text: str) -> list[str]:
    return re.findall(r"`([^`]+)`", text) + re.findall(r"https?://\S+", text)


def require_evidence(refs: list[str]) -> None:
    bad = [r for r in refs if not ref_ok(r)]
    if not refs or bad:
        raise Fail("evidence must be at least one repo path, URL or commit that resolves"
                   + (f"; these do not: {', '.join(bad)}" if bad else "; none given")
                   + ". Cite the test, run folder, ledger row or commit that backs it.")


def evidence_block(refs: list[str]) -> str:
    return "\n".join(f"- {r}" if r.startswith("http") else f"- `{r}`" for r in refs)


# ---------------------------------------------------------------- validation (the format and content gate)
def violations() -> list[str]:
    out: list[str] = []
    agents_text = AGENTS.read_text(encoding="utf-8") if AGENTS.exists() else ""
    if get_block(agents_text, BLOCK) != BLOCK_BODY:
        out.append("AGENTS.md: the backlog block is missing, duplicated or hand-edited. Run: python3 tools/backlog.py init")
    tasks = docs("tasks", "completed", "archive")
    decisions = docs("decisions")
    ids = [d.id for d in tasks + decisions]
    out += [f"duplicate id {i}" for i in sorted({i for i in ids if ids.count(i) > 1})]
    for d in tasks:
        where = d.path.relative_to(ROOT)
        out += [f"{where}: missing front matter key '{k}'" for k in TASK_KEYS if k not in d.meta]
        if not d.path.name.startswith(f"{d.id} - "):
            out.append(f"{where}: file name must start with '{d.id} - '")
        status = d.meta.get("status")
        if status not in STATUSES:
            out.append(f"{where}: status '{status}' is not one of {sorted(STATUSES)}")
        folder = d.path.parent.name
        expected = {"tasks": {"To Do", "In Progress"}, "completed": {"Done"}, "archive": {"Cancelled"}}[folder]
        if status in STATUSES and status not in expected:
            out.append(f"{where}: status '{status}' does not belong in backlog/{folder}/")
        if status == "In Progress" and not d.section("Handoff"):
            out.append(f"{where}: In Progress with an empty Handoff. Run: backlog.py handoff {d.id} --state ... --next ...")
        if status == "Done":
            refs = refs_in(d.section("Evidence"))
            if not refs or not all(map(ref_ok, refs)):
                out.append(f"{where}: Done needs an Evidence section whose every reference resolves")
            if not d.section("Final Summary"):
                out.append(f"{where}: Done needs a Final Summary")
        out += [f"{where}: dependency {dep} does not exist" for dep in d.meta.get("dependencies") or [] if dep not in ids]
    for d in decisions:
        where = d.path.relative_to(ROOT)
        out += [f"{where}: missing front matter key '{k}'" for k in DECISION_KEYS if k not in d.meta]
        if not d.path.name.startswith(f"{d.id} - "):
            out.append(f"{where}: file name must start with '{d.id} - '")
        if d.meta.get("origin") not in ORIGINS:
            out.append(f"{where}: origin must be one of {sorted(ORIGINS)}")
        out += [f"{where}: empty '{s}' section" for s in ("Context", "Decision") if not d.section(s)]
        refs = refs_in(d.section("Evidence"))
        if d.meta.get("origin") == "evidence" and (not refs or not all(map(ref_ok, refs))):
            out.append(f"{where}: origin 'evidence' needs an Evidence section whose every reference resolves")
    return out


# ---------------------------------------------------------------- the index (generated, git-ignored)
def ready(task: Doc, done_ids: set[str]) -> bool:
    return task.meta.get("status") == "To Do" and all(dep in done_ids for dep in task.meta.get("dependencies") or [])


def last_handoff(d: Doc) -> str:
    lines = [line for line in d.section("Handoff").splitlines() if line.startswith("- ")]
    return lines[-1][2:] if lines else ""


def external_decisions() -> list[str]:
    """Read-only rows for decision folders kept in another format (sources.json: {"type": "adr", "path": ...})."""
    rows = []
    for cfg in (c for c in load_sources() if c.get("type") == "adr"):
        for f in sorted((ROOT / cfg["path"]).glob("[0-9]*.md"), reverse=True):
            text = f.read_text(encoding="utf-8")
            title = next((line[2:].strip() for line in text.splitlines() if line.startswith("# ")), f.stem)
            status = re.search(r"^\W*Status\W*:?\W*(\w+)", text, re.M | re.I)
            if not f.stem.startswith("0000"):
                rows.append(f"- {title}{f' · {status.group(1)}' if status else ''}  `{f.relative_to(ROOT)}`")
    return rows


def render_index() -> str:
    tasks, completed, decisions = docs("tasks"), docs("completed"), docs("decisions")
    done_ids = {d.id for d in completed}
    active = [d for d in tasks if d.meta.get("status") == "In Progress"]
    todo = sorted((d for d in tasks if ready(d, done_ids)), key=lambda d: id_num(d.id))
    blocked = [d for d in tasks if d.meta.get("status") == "To Do" and not ready(d, done_ids)]

    def row(d: Doc, extra: str = "") -> str:
        issue = re.search(r"/issues/(\d+)$", str(d.meta.get("source", "")))
        tag = f" (issue #{issue.group(1)})" if issue else ""
        return f"- **{d.id}**{tag} {d.meta.get('title', '')}{extra}  `{d.path.relative_to(ROOT)}`"

    def active_row(d: Doc) -> str:
        claim = read_claim(d.id)
        owner = f"{claim['agent']} on {claim['branch'] or '?'}" + (" (EXPIRED claim)" if expired(claim) else "") \
            if claim else "no live claim on this machine"
        return row(d, f" · {owner}\n  - last: {last_handoff(d) or '(none)'}")

    lines = ["<!-- GENERATED by tools/backlog.py, git-ignored. Edit the task and decision files, never this. -->",
             f"# Backlog index · {stamp()}", "",
             f"{len(active)} in progress · {len(todo)} ready · {len(blocked)} blocked · "
             f"{len(completed)} done · {len(decisions) + len(external_decisions())} decisions", "",
             "## In progress", *([active_row(d) for d in active] or ["- none"]), "",
             "## Ready", *([row(d) for d in todo] or ["- none"]), "",
             *(["## Blocked", *(row(d, f" · waits on {', '.join(d.meta.get('dependencies'))}") for d in blocked), ""]
               if blocked else []),
             "## Decisions (newest first)",
             *(row(d, f" · {d.meta.get('date', '')} · {d.meta.get('status', '')}")
               for d in sorted(decisions, key=lambda d: id_num(d.id), reverse=True)),
             *external_decisions(), "",
             "## Recently done",
             *(row(d, f" · {d.meta.get('completed_date', '')}")
               for d in sorted(completed, key=lambda d: str(d.meta.get("completed_date", "")), reverse=True)[:10]),
             ""]
    return "\n".join(lines)


def write_index() -> str:
    text = render_index()
    write_atomic(INDEX, text)
    return text


# ---------------------------------------------------------------- commands
def cmd_init(a) -> None:
    for d in DIRS.values():
        d.mkdir(parents=True, exist_ok=True)
    readme = BACKLOG / "README.md"
    if not readme.exists() or a.refresh_readme:
        write_atomic(readme, README)
    upsert_block(AGENTS, BLOCK, BLOCK_BODY)
    claude = ROOT / "CLAUDE.md"
    if not claude.exists():
        write_atomic(claude, "@AGENTS.md\n")
    elif "AGENTS.md" not in claude.read_text(encoding="utf-8"):
        upsert_block(claude, BLOCK, "@AGENTS.md")
    gitignore = ROOT / ".gitignore"
    present = gitignore.read_text(encoding="utf-8").splitlines() if gitignore.exists() else []
    missing = [line for line in GITIGNORE_LINES if line not in present]
    if missing:
        write_atomic(gitignore, "\n".join(present + ([""] if present else []) + missing) + "\n")
    hook = ROOT / ".githooks" / "pre-commit"
    lines = hook.read_text(encoding="utf-8").splitlines() if hook.exists() else ["#!/bin/sh"]
    if PRE_COMMIT_LINE not in lines:
        at = 1 if lines and lines[0].startswith("#!") else 0
        lines[at:at] = ["# Refuse a commit that leaves the backlog invalid (tools/backlog.py).", PRE_COMMIT_LINE]
        if not hook.exists():
            lines.append("exit 0")
        hook.parent.mkdir(parents=True, exist_ok=True)
        write_atomic(hook, "\n".join(lines) + "\n")
    hook.chmod(0o755)
    settings = ROOT / ".claude" / "settings.json"
    cfg = json.loads(settings.read_text(encoding="utf-8")) if settings.exists() else {}
    starts = cfg.setdefault("hooks", {}).setdefault("SessionStart", [])
    if SETTINGS_HOOK not in [h.get("command") for entry in starts for h in entry.get("hooks", [])]:
        starts.append({"hooks": [{"type": "command", "command": SETTINGS_HOOK}]})
        settings.parent.mkdir(parents=True, exist_ok=True)
        write_atomic(settings, json.dumps(cfg, indent=2) + "\n")
    note = set_hooks_path()
    if note:
        print(note)
    write_index()
    print("backlog: initialised (AGENTS.md block, CLAUDE.md, .gitignore, .githooks/pre-commit, .claude/settings.json)")


def cmd_index(a) -> None:
    print(write_index())


def cmd_brief(a) -> None:
    note = set_hooks_path() if (ROOT / ".githooks" / "pre-commit").exists() else ""
    if note:
        print(note)
    text = write_index()
    head, _, rest = text.partition("## Decisions")
    decisions = rest.split("\n## ", 1)[0].strip().splitlines()[1:6]
    print("\n".join(head.splitlines()[1:]).rstrip())
    print("\n## Latest decisions (all: backlog/INDEX.md)\n" + ("\n".join(decisions) or "- none"))
    problems = violations()
    if problems:
        print(f"\n!! backlog check: {len(problems)} violation(s). Run: python3 tools/backlog.py check")
    print("\nRules: claim before you work · handoff before you stop or when context runs low · "
          "done needs evidence · a choice between methods becomes a decision. See backlog/README.md.")


def cmd_check(a) -> None:
    problems = violations()
    if problems:
        print("backlog check FAILED:\n" + "\n".join(f"- {p}" for p in problems))
        sys.exit(1)
    if not a.quiet:
        print("backlog check: ok")


def cmd_new(a) -> None:
    task_id = next_id("task")
    sections = {"Description": a.description or "",
                "Acceptance Criteria": "\n".join(f"- [ ] {c}" for c in a.ac),
                "Handoff": "", "Evidence": "", "Final Summary": ""}
    meta = {"id": task_id, "title": a.title, "status": "To Do", "assignee": [], "created_date": today(),
            "updated_date": today(), "labels": a.label, "dependencies": a.dep}
    meta.update({"source": a.source} if a.source else {})
    doc = Doc(DIRS["tasks"] / f"{task_id} - {slug(a.title)}.md", meta, sections)
    doc.save()
    write_index()
    print(f"{task_id}  {doc.path.relative_to(ROOT)}")


def cmd_claim(a) -> None:
    doc = find(a.id)
    if doc.path.parent != DIRS["tasks"]:
        raise Fail(f"{a.id} is in backlog/{doc.path.parent.name}/, only open tasks can be claimed")
    claim = refuse_if_foreign(a.id, a.agent)
    if claim and claim["agent"] != a.agent:
        tomb = claim_path(a.id).with_suffix(f".expired-{os.getpid()}")
        try:
            os.rename(claim_path(a.id), tomb)
            moved = json.loads(tomb.read_text(encoding="utf-8"))
            if moved["claimed_at"] != claim["claimed_at"]:
                os.rename(tomb, claim_path(a.id))
                raise Fail(f"{a.id} was re-claimed by {moved['agent']} while you were taking over the expired claim")
        except FileNotFoundError:
            pass
    try:
        write_claim(a.id, a.agent, a.ttl_hours, exclusive=not (claim and claim["agent"] == a.agent))
    except FileExistsError:
        raise Fail(f"{a.id} was claimed by another agent a moment ago: {read_claim(a.id)}")
    branch = git("branch", "--show-current")
    doc.meta.update(status="In Progress", assignee=[a.agent], updated_date=today())
    doc.append("Handoff", f"- {stamp()} · {a.agent} · {branch}: claimed. Next: {a.next}")
    doc.save()
    write_index()
    print(f"claimed {a.id} for {a.agent} until {read_claim(a.id)['expires_at']}")


def cmd_handoff(a) -> None:
    doc = find(a.id)
    claim = refuse_if_foreign(a.id, a.agent)
    branch = git("branch", "--show-current")
    doc.append("Handoff", f"- {stamp()} · {a.agent} · {branch}: {a.state} Next: {a.next}")
    doc.meta["updated_date"] = today()
    doc.save()
    if claim and claim["agent"] == a.agent:
        write_claim(a.id, a.agent, a.ttl_hours, exclusive=False)
    write_index()
    print(f"handoff recorded on {a.id}")


def cmd_release(a) -> None:
    doc = find(a.id)
    claim = refuse_if_foreign(a.id, a.agent)
    if claim:
        claim_path(a.id).unlink(missing_ok=True)
    doc.meta.update(status="To Do", assignee=[], updated_date=today())
    doc.append("Handoff", f"- {stamp()} · {a.agent}: released, back to To Do.")
    doc.save()
    write_index()
    print(f"released {a.id}")


def move(doc: Doc, folder: str) -> None:
    target = DIRS[folder] / doc.path.name
    target.parent.mkdir(parents=True, exist_ok=True)
    tracked = git("ls-files", "--error-unmatch", str(doc.path.relative_to(ROOT)))
    if tracked:
        git("mv", str(doc.path.relative_to(ROOT)), str(target.relative_to(ROOT)))
    else:
        shutil.move(doc.path, target)
    doc.path = target


def cmd_done(a) -> None:
    doc = find(a.id)
    refuse_if_foreign(a.id, a.agent)
    if not doc.section("Handoff"):
        raise Fail(f"{a.id} has no Handoff trail. Record one first: backlog.py handoff {a.id} --state ... --next ...")
    require_evidence(a.evidence)
    if not a.summary.strip():
        raise Fail("--summary is required: two lines a later agent can trust without re-reading the diff")
    doc.sections["Evidence"] = evidence_block(a.evidence)
    doc.sections["Final Summary"] = a.summary.strip()
    doc.meta.update(status="Done", updated_date=today(), completed_date=today())
    move(doc, "completed")
    doc.save()
    claim_path(a.id).unlink(missing_ok=True)
    write_index()
    print(f"done {a.id} -> {doc.path.relative_to(ROOT)}")


def cmd_cancel(a) -> None:
    doc = find(a.id)
    doc.meta.update(status="Cancelled", updated_date=today())
    doc.sections["Final Summary"] = f"Cancelled: {a.reason}"
    move(doc, "archive")
    doc.save()
    claim_path(a.id).unlink(missing_ok=True)
    write_index()
    print(f"cancelled {a.id} -> {doc.path.relative_to(ROOT)}")


def cmd_decide(a) -> None:
    if a.origin == "evidence":
        require_evidence(a.evidence)
    decision_id = next_id("decision")
    meta = {"id": decision_id, "title": a.title, "date": a.date or today(), "status": "accepted",
            "origin": a.origin, "tasks": a.task}
    sections = {"Context": a.context, "Options Considered": a.options, "Decision": a.decision,
                "Evidence": evidence_block(a.evidence), "Consequences": a.consequences or ""}
    doc = Doc(DIRS["decisions"] / f"{decision_id} - {slug(a.title)}.md", meta, sections)
    doc.save()
    write_index()
    print(f"{decision_id}  {doc.path.relative_to(ROOT)}")


# ---------------------------------------------------------------- optional sources (one function per type)
def github_issues(cfg: dict) -> list[dict]:
    if not shutil.which("gh"):
        raise Fail("source 'github' needs the gh CLI on PATH")
    env = dict(os.environ, **({"GH_CONFIG_DIR": os.path.expanduser(cfg["gh_config_dir"])}
                              if cfg.get("gh_config_dir") else {}))
    r = subprocess.run(["gh", "issue", "list", "-R", cfg["repo"], "--state", "all", "-L", "500",
                        "--json", "number,title,body,labels,url,state"], capture_output=True, text=True, env=env)
    if r.returncode != 0:
        raise Fail(f"gh issue list failed for {cfg['repo']}: {r.stderr.strip()}")
    return [{"ref": i["url"], "title": i["title"], "body": i.get("body") or "", "open": i["state"] == "OPEN",
             "labels": [lbl["name"] for lbl in i.get("labels", [])]} for i in json.loads(r.stdout)]


SOURCE_TYPES = {"github": github_issues}


def load_sources() -> list[dict]:
    return json.loads(SOURCES.read_text(encoding="utf-8")) if SOURCES.exists() else []


def cmd_sync(a) -> None:
    if not SOURCES.exists():
        print("backlog: no backlog/sources.json, nothing to sync (sources are optional)")
        return
    linked = {d.meta.get("source"): d for d in docs("tasks", "completed", "archive") if d.meta.get("source")}
    for cfg in (c for c in load_sources() if c["type"] in SOURCE_TYPES):
        items = SOURCE_TYPES[cfg["type"]](cfg)
        for item in (i for i in items if i["open"] and i["ref"] not in linked):
            ns = argparse.Namespace(title=item["title"], description=f"Imported from {item['ref']}\n\n{item['body']}".strip(),
                                    ac=[], label=item["labels"], dep=[], source=item["ref"])
            cmd_new(ns)
        stale = [linked[i["ref"]].id for i in items if not i["open"] and i["ref"] in linked
                 and linked[i["ref"]].path.parent == DIRS["tasks"]]
        if stale:
            print(f"closed at the source but open here (close them with done/cancel): {', '.join(stale)}")


# ---------------------------------------------------------------- cli
def main() -> None:
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = p.add_subparsers(dest="cmd", required=True)
    agent = {"default": default_agent(), "help": "who is acting (env BACKLOG_AGENT, else user@worktree)"}
    s = sub.add_parser("init"); s.add_argument("--refresh-readme", action="store_true"); s.set_defaults(fn=cmd_init)
    sub.add_parser("brief").set_defaults(fn=cmd_brief)
    sub.add_parser("index").set_defaults(fn=cmd_index)
    s = sub.add_parser("check"); s.add_argument("--quiet", action="store_true"); s.set_defaults(fn=cmd_check)
    s = sub.add_parser("new"); s.add_argument("title"); s.add_argument("--description", default="")
    s.add_argument("--ac", action="append", default=[]); s.add_argument("--label", action="append", default=[])
    s.add_argument("--dep", action="append", default=[]); s.add_argument("--source", default="")
    s.set_defaults(fn=cmd_new)
    s = sub.add_parser("claim"); s.add_argument("id"); s.add_argument("--next", required=True)
    s.add_argument("--agent", **agent); s.add_argument("--ttl-hours", type=float, default=DEFAULT_TTL_HOURS)
    s.set_defaults(fn=cmd_claim)
    s = sub.add_parser("handoff"); s.add_argument("id"); s.add_argument("--state", required=True)
    s.add_argument("--next", required=True); s.add_argument("--agent", **agent)
    s.add_argument("--ttl-hours", type=float, default=DEFAULT_TTL_HOURS); s.set_defaults(fn=cmd_handoff)
    s = sub.add_parser("release"); s.add_argument("id"); s.add_argument("--agent", **agent); s.set_defaults(fn=cmd_release)
    s = sub.add_parser("done"); s.add_argument("id"); s.add_argument("--evidence", nargs="+", default=[])
    s.add_argument("--summary", default=""); s.add_argument("--agent", **agent); s.set_defaults(fn=cmd_done)
    s = sub.add_parser("cancel"); s.add_argument("id"); s.add_argument("--reason", required=True)
    s.set_defaults(fn=cmd_cancel)
    s = sub.add_parser("decide"); s.add_argument("title"); s.add_argument("--context", required=True)
    s.add_argument("--options", required=True); s.add_argument("--decision", required=True)
    s.add_argument("--evidence", nargs="+", default=[]); s.add_argument("--consequences", default="")
    s.add_argument("--origin", choices=sorted(ORIGINS), default="evidence"); s.add_argument("--date", default="")
    s.add_argument("--task", action="append", default=[]); s.set_defaults(fn=cmd_decide)
    sub.add_parser("sync").set_defaults(fn=cmd_sync)
    a = p.parse_args()
    try:
        a.fn(a)
    except Fail as e:
        print(f"backlog: {e}", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
