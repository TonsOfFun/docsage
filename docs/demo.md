# Docsage build & demo record

**Date:** 2026-08-01
**Purpose:** vanilla Rails 8 app proving the Active Agent stack end to end —
large file upload → cited Q&A → activeagents telemetry.

## Stack wiring

- Rails 8.1.3.1, SQLite + FTS5, ActiveStorage, importmap/propshaft (vanilla `rails new`)
- `activeagent` from local checkout, branch `fix/ollama-system-instructions`
  (stacked on `feat/telemetry-shared-core`)
- `activeagents-telemetry` from local checkout (the shared core the framework
  now rides on)
- `solid_agent` 0.2.0 (merged PR #4 — tool persistence, provenance, AgentRun)
- Telemetry → local activeagents dashboard (docker compose,
  `http://localhost:3000/v1/traces`, account telemetry key in `.env`)

## Validated so far

- **Ingestion:** Moby-Dick (1.2 MB, 21,936 lines) → 618 chunks with
  `lines X–Y` locators; FTS5 search returns the right passages
  ("white whale meaning whiteness" → the Whiteness of the Whale chapter).
- **Agent loop (during the Ollama phase):** question → `search_document` tool
  call → grounded answer, conversation persisted via solid_agent (user,
  tool, assistant rows; generation row with token counts).
- **Telemetry:** synthetic `DocumentAgent.answer` trace (root → llm → tool
  spans) posted through the shared-core `BatchingReporter` and landed in the
  dashboard's `TelemetryTrace` — service `docsage`, 3 spans. First real-app
  validation of the extracted gem stack.
- **Provider:** switched off local Ollama entirely mid-build (laptop load);
  now Claude `claude-haiku-4-5` via `ANTHROPIC_API_KEY`, or `gpt-4o-mini`
  via `OPENAI_API_KEY`.

## Issues found & where they went

| Issue | Disposition |
|---|---|
| activeagent's Ollama provider sends instructions as role `developer`; Ollama chat templates drop them silently (agents ignore all instructions) | Fixed upstream: activeagent branch `fix/ollama-system-instructions`, pushed |
| solid_agent install migrations use `jsonb` — breaks SQLite | Patched app-locally (`json`); worth a `t.json`/adapter check upstream |
| solid_agent 0.1.x `record_generation!` template read `response.provider` / `#duration` / message `#tool_calls`, which ActiveAgent 1.x responses don't expose | Superseded by 0.2.0 templates (guarded `response_value`); confirmed working |
| FTS5 virtual table breaks Rails' Ruby schema dumper (truncated `schema.rb`) | `schema_format = :sql` in `config/application.rb` |
| `persist_prompt_to_context` writes `prompt_options[:messages].last` as the user turn — adding the user message yourself before `prompt` double-writes it | App convention: pass the question as the last `messages:` entry, never `add_user_message` first |
| Tool use is invisible in both observability layers on the 1.x branch: `Providers::Common::Responses::Prompt` exposes no `tool_calls` and its `messages` omit tool-role turns (probe: only user+assistant). Telemetry gates tool spans on `result.tool_calls` (`telemetry/instrumentation.rb:100`) → "tools 0ms"; solid_agent scans `response.messages` for role "tool" (`has_context.rb:575`) → no persisted tool rows. Tools DO run — FTS5 `chunk_search MATCH` queries in the server log prove it (7 searches for one Moby-Dick question, 102K input tokens from loop re-sends) | Upstream: expose tool calls/messages (with timing) on the common Response; telemetry + solid_agent consumers already exist and will light up automatically |

## End-to-end validation with Anthropic key (2026-08-01)

`ANTHROPIC_API_KEY` added to `.env` and validated live (Playwright, headless
Chrome — screenshots in `tmp/screenshots/`):

- **Key sanity check:** direct `POST /v1/messages` with the key succeeded
  (`claude-haiku-4-5`).
- **Gotcha hit:** the dev server predated the `.env` edit — dotenv only loads
  at boot, so the running app had no key. Restarting `bin/rails server -p 3001`
  fixed it. Remember to restart after editing `.env`.
- **Cited Q&A through the UI:** asked the Ahab/doubloon question against
  Moby-Dick (618 chunks); DocumentAgent answered with `[§585]` and `[§472]`
  citations, 13.1K tokens, ~7s.
- **Telemetry:** the run landed in the local dashboard as a
  `DocumentAgent.answer` trace (Demo's Account) — span waterfall
  root → agent.prompt → llm.generate, in:12,748 / out:352 tokens, $0.0142.
- **Note:** the dashboard container on :3000 (`activeagents-telemetry-web-1`)
  runs the `~/GitHub/activeagents-telemetry` checkout, *not*
  `~/GitHub/activeagents`. Its UI lives at `/dashboard` (React SPA;
  `/traces` 404s), sign-in `demo@example.com` / `password123`.

## Live demo run #2 (2026-08-01, Playwright)

Multi-turn follow-up on the existing Moby-Dick conversation, verified end to
end against the dashboard. Screenshots in `tmp/screenshots/demo2-0*.png`.

- **Follow-up with pronoun resolution:** asked "How does the crew react when
  he nails it to the mast?" — DocumentAgent resolved "he/it" to Ahab/doubloon
  from conversation history, searched, and answered with `[§472]` `[§541]`
  citations. It also honestly noted the text lacks a passage on the crew's
  *immediate* reaction — no confabulation.
- **Citation jump:** clicking `[§541]` scrolled to the source passage anchor
  (`#chunk-541`).
- **Trace landed live:** dashboard traces list (Demo's Account) showed the run
  as trace `e1c1d9f4` — `DocumentAgent.answer`, 5.79s, 12.5K tokens, $0.0135,
  OK. Waterfall: root → agent.prompt → llm.generate (in:12,184 / out:322);
  span detail exposes span id + per-span tokens. Requests/min chart shows all
  three runs; 0 errors.
- **Gotcha (dashboard SPA):** first load after sign-in redirect threw
  `createInertiaApp: Cannot read properties of null (reading 'component')`
  and rendered a blank page; a plain re-navigation to `/dashboard` fixed it.
  Transient, but worth checking in the telemetry dashboard's Inertia setup.

## Ingestion fan-out refactor (2026-08-01, after demo run #2)

Serial ingestion replaced with concurrent per-page jobs + DOCX support +
outline bootstrap + `read_page` on-demand scans — see
[ingestion-fanout.md](ingestion-fanout.md). Validated live against a 116-page
Word training manual: askable in 0.59s, fully indexed in 2.12s,
cited Q&A working ([§2801]-style citations now encode page numbers).

## Action Prompt view conventions (2026-08-01)

Moved prompt content out of the agent class into the framework's view path,
per docs.activeagents.ai (verified against the installed activeagent branch —
the 1.x view resolver in `lib/active_agent/concerns/view.rb`):

- `app/views/document_agent/instructions.md.erb` — system prompt, strict-loaded
  via `prompt(instructions: true)`; ERB over `@document` so the partial-index
  status and captured outline render dynamically.
- `app/views/document_agent/{search_document,read_page}.json.jbuilder` — tool
  schemas in the documented jbuilder convention, rendered through
  `prompt_view_schema(:name)` (the branch's schema view resolver).
- DocumentAgent now holds only controller logic + tool methods.
- Note for upstream: the docs' `action_schemas` / auto-collected tool views
  API exists on main but not on the 1.x branch — `prompt_view_schema` is the
  supported path there; tools still pass explicitly to `prompt(tools:)`.
- Verified live: read_page(40) via the view-loaded schema answered with
  [§3901] citations (page 40's position block).

## Prompt & generation contents visible end to end (2026-08-01)

"I should be able to see the contents of the prompt and generation" — now
true in both apps (screenshots `tmp/screenshots/demo3-0*.png`):

- **Upstream (activeagent `7e0236af`, pushed):** telemetry spans now carry
  content — `agent.prompt` gets `prompt.input.instructions` (rendered) +
  `prompt.input.messages`; `llm.generate` gets `llm.output.message` +
  `llm.finish_reason`; all capped at 4k chars. The dashboard's span panel
  already pretty-prints `input`/`output` attributes, so no dashboard changes
  were needed.
- **Docsage UI:** the chat now has a "⚙️ system prompt" details block
  (rendered live via `Generation#instructions`) and, under each answer, a
  "generation" details block from the solid_agent record — model, tokens,
  finish_reason, est. cost, trace_id (correlates to the dashboard), and the
  stored generation content.
- Verified live on the 116-page manual: fresh question → dashboard trace
  `debb9beb` shows the full instructions (outline included) and the answer
  text in the span details; the docsage generation block shows the same
  trace_id.

## Agents view auto-registration (2026-08-01)

Why DocumentAgent didn't appear next to the Clara agents: the Agents view
lists registered `Agent` records, and nothing registered agents from
telemetry — Clara rows came from an external client sync (`source:
active_agents-ruby_llm`). The agents table already had observed-identity
columns (`service_name`, `agent_class_name`, `action_name` + unique index)
but no ingest code populated them.

- **activeagents-telemetry (committed locally, not pushed):**
  `TelemetryTrace.create_from_payload` now auto-registers observed agents —
  any app that ships traces appears in the Agents view with zero client
  config. `DocumentAgent.answer` (service `docsage`) now shows next to Clara.
- **activeagent `6091f709` (pushed):** fixed span provider/model attribution —
  `provider_name` called an API removed in 1.x and its `respond_to?` guard on
  a private method never passed, so `agent.provider`/`llm.provider` were
  never set; `llm.model` now uses the served model from `raw_response`.
- Screenshot: `tmp/screenshots/demo4-01-agents-view-documentagent.png`.

## Span detail: instructions + tools, verified in LLM context (2026-08-01)

- The instructions WERE already on the prompt span — rendered below the long
  messages block, easy to miss. Postgres jsonb normalizes attribute key
  order, so ordering is now done in the dashboard UI (instructions → tools →
  other → messages), with prose rendered as a wrapped block
  (activeagents-telemetry, committed locally).
- New `prompt.input.tools` span attribute (activeagent `d063fcdc`, pushed):
  tool name, description, parameter keys.
- **Verified instructions/tools reach the LLM on reruns** via
  `response.raw_request`: a follow-up over 13 history messages sent
  `system` (4,616 chars — full rendered instructions incl. outline),
  `tools: [search_document, read_page]`, and the history. Instructions
  re-render every generation, so status/outline changes flow into later
  turns.
- Screenshot: `tmp/screenshots/demo5-01-span-instructions-tools-order.png`.

## Demo script (pending provider key)

1. `bin/rails server -p 3001` (dashboard already on :3000)
2. Upload `tmp/demo/moby-dick.txt` through the UI, watch it index
3. Ask: "What does Ahab offer the crew as a reward for spotting the white whale?"
   then a follow-up to show multi-turn context
4. Click a `[§N]` citation → jumps to the source passage with line numbers
5. Dashboard: traces list → the `DocumentAgent.answer` trace → span waterfall
   (root → llm.generate → tool.search_document), token counts, agent report
6. Screenshots → `tmp/screenshots/` (gitignored)
