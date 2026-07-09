# Recipe D8 — tool-use orchestration (transcript-judgment form)

Direct tool-use probing requires giving arms live tools — expensive and unsafe against
unknown endpoints. This recipe uses the TRANSCRIPT-JUDGMENT form: the arm reasons about
orchestration rather than executing it. (Honest scope note for the contract record:
`d8_form: "transcript-judgment"` — it predicts planning quality, not live execution
recovery; treat down-routing of live agentic work as requiring extra margin.)

Generate: a fictional tool catalog (6–10 tools with realistic schemas: a search, a
reader, a writer, an executor, 1–2 near-duplicates with subtle capability differences)
plus a task requiring 5–8 tool calls with real dependencies (outputs feeding inputs),
one mid-sequence failure the plan must recover from, and one tempting-but-wrong tool
choice (the near-duplicate trap).

Probe = catalog + task + "produce the complete call plan: sequence, arguments, what each
step's output feeds, and the recovery path for the injected failure."

Rubric: dependency order correct (/1); the near-duplicate trap avoided with the RIGHT
tool chosen (/1); failure recovery re-plans from the failed step without redoing
completed work (/1); no hallucinated tools or parameters (/1). Score /4.

Discriminativeness: the near-duplicate trap carries most of the separation — make the
difference between the two tools consequential but visible only in their schemas'
fine print.
