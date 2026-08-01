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

## Demo script (pending provider key)

1. `bin/rails server -p 3001` (dashboard already on :3000)
2. Upload `tmp/demo/moby-dick.txt` through the UI, watch it index
3. Ask: "What does Ahab offer the crew as a reward for spotting the white whale?"
   then a follow-up to show multi-turn context
4. Click a `[§N]` citation → jumps to the source passage with line numbers
5. Dashboard: traces list → the `DocumentAgent.answer` trace → span waterfall
   (root → llm.generate → tool.search_document), token counts, agent report
6. Screenshots → `tmp/screenshots/` (gitignored)
