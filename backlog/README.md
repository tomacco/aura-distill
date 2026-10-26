# Backlog

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
