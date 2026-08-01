# Answers questions about one uploaded document, grounded in retrieved
# passages and citing every claim. Each ask is a standalone exchange (its
# own context/run/trace), not a turn in a rolling conversation.
#
# The model cannot see the document directly — it must call search_document
# (FTS5 over indexed chunks) or read_page (full page, indexed on demand).
# Instructions require answers to cite §N tags, and the UI resolves each
# [§N] back to the exact passage (with its line/page locator) it came from.
#
# Prompt content lives in the Action Prompt view path, per framework
# conventions (app/views/document_agent/):
#   instructions.md.erb           — system prompt (strict-loaded, ERB over @document)
#   search_document.json.jbuilder — tool schema, rendered via prompt_view_schema
#   read_page.json.jbuilder       — tool schema, rendered via prompt_view_schema
class DocumentAgent < ApplicationAgent
  include SolidAgent::HasContext

  # auto_save persists the whole exchange from the response: the user turn
  # (last prompt message), every tool call/result message, and the generation
  # with provenance + trace correlation.
  has_context contextual: false, auto_save: true

  def answer
    @document = document
    # One-shot exchange: every ask gets its own fresh context — one run, one
    # session, one trace. No conversation history is replayed; each question
    # must stand alone and be answered from tool results.
    create_context(contextable: document)

    tools = [ prompt_view_schema(:search_document) ]
    tools << prompt_view_schema(:read_page) if document.page_count.positive?

    prompt(
      messages: [ { role: "user", content: params[:question] } ],
      tools: tools,
      instructions: true # strict-load app/views/document_agent/instructions.md.erb
    )
  end

  # Tool: FTS5 search over the indexed chunks.
  def search_document(query:)
    chunks = document.search_chunks(query, limit: 5)
    return "No passages matched #{query.inspect}. Try different or fewer terms." if chunks.empty?

    chunks.map { |chunk|
      "[#{chunk.reference} · #{chunk.locator}]\n#{chunk.content}"
    }.join("\n\n---\n\n")
  end

  # Tool: read one page in full, indexing it on demand if the fan-out jobs
  # haven't reached it yet (real-time scan).
  def read_page(number:)
    page = document.pages.find_by(number: number.to_i)
    return "No page #{number} — this document has pages 1–#{document.page_count}." unless page

    PageIndexer.new(page).call unless page.indexed?

    page.chunks.order(:position).map { |chunk|
      "[#{chunk.reference} · #{chunk.locator}]\n#{chunk.content}"
    }.join("\n\n---\n\n").presence || "Page #{number} has no extractable text."
  end

  private

  def document
    params[:document]
  end
end
