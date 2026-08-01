# Docsage

A vanilla Rails 8 demo app for the Active Agent stack: upload a large
document, ask it questions, get answers that cite their sources — with every
agent interaction traced to an ActiveAgents dashboard.

Built on:

| Piece | Role |
|---|---|
| [activeagent](https://github.com/activeagents/activeagent) (`feat/telemetry-shared-core` + `fix/ollama-system-instructions`) | Agent framework — `DocumentAgent` is a controller with a tool-calling action |
| [solid_agent](https://github.com/activeagents/solid_agent) 0.2.0 | Persists the conversation: user turns, tool calls/results, generations with tokens & provenance |
| [activeagents-telemetry](https://github.com/activeagents/activeagents-telemetry) | Ships every generation as a trace (root → llm → tool spans) to the dashboard |

## How it works

1. **Upload** (`.txt`/`.md`/`.pdf`, ActiveStorage) → `IngestDocumentJob` extracts
   text and chunks it on paragraph boundaries (~1.5k chars) with line/page
   locators, indexed into SQLite **FTS5**.
2. **Ask** → `DocumentAgent#answer` prompts with the conversation history and a
   single tool, `search_document(query:)`. The model can't see the document —
   it must search, and passages come back tagged `§N`.
3. **Cite** → instructions require `[§N]` after every claim; the UI links each
   citation to the exact passage (with its `lines X–Y` / `page N` locator).
4. **Trace** → the framework's telemetry (riding on `activeagents-telemetry`)
   posts one trace per generation to the dashboard configured in `.env`.

## Run it

```bash
bundle install
bin/rails db:prepare

# .env (gitignored):
#   ANTHROPIC_API_KEY=…            ← or OPENAI_API_KEY
#   ACTIVEAGENTS_API_KEY=…         ← account telemetry key or platform API key
#   ACTIVEAGENTS_TELEMETRY_ENDPOINT=http://localhost:3000/v1/traces

bin/rails server -p 3001
```

The local ActiveAgents dashboard comes up with
`docker compose -f docker-compose.dev.yml up` in the activeagents repo.

Provider selection is automatic: Claude (`claude-haiku-4-5`) when
`ANTHROPIC_API_KEY` is set, else OpenAI (`gpt-4o-mini`). Leaving
`ACTIVEAGENTS_API_KEY` unset disables telemetry entirely.

## Notes

- FTS5 forces `schema_format = :sql` — Rails' Ruby schema dumper can't
  represent virtual tables.
- solid_agent's migration templates use `jsonb`; on SQLite they're patched to
  `json` (see `db/migrate/`).
- `docs/demo.md` records the demo run and the issues found along the way.
