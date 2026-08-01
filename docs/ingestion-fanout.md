# Milestone: concurrent page-fan-out ingestion (2026-08-01)

Replaced the serial one-job ingestor with a two-phase pipeline built around
`DocumentPage` records, so large documents index concurrently and become
askable within a second of upload.

## Why

The original `DocumentIngestor` extracted every page in series and wrote all
chunks in one transaction — nothing was searchable until the whole document
finished, and `.docx` files (a common format for course-material and training
sources) weren't parsed at all: anything non-PDF fell into the plain-text
branch and chunked as zip garbage.

## Architecture

```
Upload → IngestDocumentJob → DocumentIngestor (phase 1: plan)
           ├─ creates DocumentPage records (status: pending)
           ├─ inline-indexes first 3–8 pages (+1 while still front-matter/TOC)
           │    └─ outline captured onto documents.outline for the agent
           └─ fans out IndexDocumentPageJob per remaining page
                └─ PageIndexer (phase 2, concurrent): extract → chunk → FTS index
                     └─ last-page job flips document to ready
```

- **Page boundaries** — PDF: real pages (planned by count only; each page job
  extracts its own page so parsing parallelizes too). DOCX: split on Word's
  `<w:lastRenderedPageBreak/>` / explicit page breaks (`DocxExtractor`, new
  `rubyzip` dep + Nokogiri). Text: ~12k-char pseudo-pages on paragraph
  boundaries, keeping real `lines X–Y` locators via `start_line`.
- **Stable citations under concurrency** — each page owns a block of 100 §N
  positions (`DocumentPage::POSITION_STRIDE`); chunk position =
  `(page-1)*100 + i`. Citations stay unique, stable, and in document order
  no matter what order jobs finish. §2801 ⇒ page 29, first chunk.
- **Askable while indexing** — `Document#askable?` opens the chat as soon as
  any page is indexed; the agent's instructions state the partial-index
  status. `documents.indexed_page_count` is bumped atomically per page job.
- **Outline bootstrap** — first 3 pages index inline, +1 page while the
  previous still classifies as outline content (short lines / dotted leaders
  / "Contents" headings), cap 8. Concatenated outline text (≤6k chars) is
  injected into agent instructions as a map of the document.
- **Real-time page scans** — new `read_page(number:)` agent tool returns a
  page's chunks; if the fan-out hasn't reached that page yet, the tool runs
  `PageIndexer` inline on demand.

## Validation

- `test/services/document_ingestor_test.rb` — 4 tests / 61 assertions: pseudo-page
  fan-out, exact line-locator round-trip, docx page-break splitting, on-demand
  page indexing. All green (`bin/rails test`).
- Live run against a real 116-page Word training manual (256 KB, gitignored):
  `script/ingest_demo.rb` → **116 pages, 177 chunks, askable in 0.59s,
  fully indexed in 2.12s**; outline captured (3.9k chars of front matter/TOC).
- End-to-end Q&A: "What is mutual inductance and what factors affect it?" →
  correct sectioned answer citing [§3101] [§2801] [§2802]; trace posted to the
  local ActiveAgents dashboard as usual.

## Notes / follow-ups

- Old documents (ingested pre-fan-out) have no pages; the agent simply omits
  the `read_page` tool for them. Chunks' `document_page_id` is nullable.
- SQLite has a single writer, so the concurrency win is mostly in extraction
  (PDF parsing per page); on the platform's Postgres the write path
  parallelizes too.
- Possible next step: a generate-outline agent action that turns the captured
  outline + read_page into course-material scaffolding (chapters → quiz
  questions with §N-cited sources).
