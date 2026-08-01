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

## Demo script (pending provider key)

1. `bin/rails server -p 3001` (dashboard already on :3000)
2. Upload `tmp/demo/moby-dick.txt` through the UI, watch it index
3. Ask: "What does Ahab offer the crew as a reward for spotting the white whale?"
   then a follow-up to show multi-turn context
4. Click a `[§N]` citation → jumps to the source passage with line numbers
5. Dashboard: traces list → the `DocumentAgent.answer` trace → span waterfall
   (root → llm.generate → tool.search_document), token counts, agent report
6. Screenshots → `tmp/screenshots/` (gitignored)
