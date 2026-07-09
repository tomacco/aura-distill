# Token Saver — raw measurements (2026-07-09)

Context floors of subagent spawns, measured with an identical trivial prompt
("Reply with exactly: OK"), model claude-haiku-4-5, Claude Code CLI on Windows.
floor = input_tokens + cache_read_input_tokens + cache_creation_input_tokens
of the run's usage record (full JSON preserved per cell).

| file | configuration | floor (tokens) |
|---|---|---|
| default.json | `claude -p`, default toolbox | 27,403 |
| scout.json | `claude -p --tools Read,Glob,Grep` | 7,873 |
| scribe.json | `claude -p --tools none` | 5,236 |
| agentdef.json | custom agent, `tools: []` frontmatter | 1,965 |

Capability verification (same day): a file-based `scout` agent read a probe file
correctly and self-reported exactly [Glob, Grep, Read]; a file-based `scribe`
agent self-reported "NO TOOLS". In-session Agent-tool check: the same one-word
task cost 18,967 tokens on a general-purpose agent vs 12,855 on the restricted
built-in Explore agent.

These numbers back docs/token-saving.html and the agents/ preset descriptions.
