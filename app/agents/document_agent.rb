# Answers questions about one uploaded document, grounded in retrieved
# passages and citing every claim.
#
# The model cannot see the document directly — it must call search_document,
# which runs FTS5 over the ingested chunks and returns passages tagged §N.
# Instructions require answers to cite those tags, and the UI resolves each
# [§N] back to the exact passage (with its line/page locator) it came from.
class DocumentAgent < ApplicationAgent
  include SolidAgent::HasContext

  # auto_save persists the whole exchange from the response: the user turn
  # (last prompt message), every tool call/result message, and the generation
  # with provenance + trace correlation.
  has_context contextual: false, auto_save: true

  READ_PAGE_TOOL = {
    name: "read_page",
    description: "Read the full text of one page of the document by page number. " \
                 "If that page hasn't been indexed yet it is scanned on demand, so this " \
                 "works even while the document is still indexing. Use it to follow the " \
                 "document's outline or a citation to a specific page.",
    parameters: {
      type: "object",
      properties: {
        number: {
          type: "integer",
          description: "1-based page number to read"
        }
      },
      required: [ "number" ]
    }
  }.freeze

  SEARCH_TOOL = {
    name: "search_document",
    description: "Full-text search this document. Returns the most relevant passages, " \
                 "each tagged with a citation reference like §12. Call it before answering; " \
                 "call it again with different terms if the first results don't answer the question.",
    parameters: {
      type: "object",
      properties: {
        query: {
          type: "string",
          description: "Search terms — significant words from the question, or synonyms on retry"
        }
      },
      required: [ "query" ]
    }
  }.freeze

  def answer
    load_context(contextable: document)

    # History is user/assistant turns only — replaying persisted tool-role
    # messages without their paired tool_use blocks breaks providers.
    history = context_messages.select { |message|
      %w[user assistant].include?((message[:role] || message["role"]).to_s)
    }

    tools = [ SEARCH_TOOL ]
    tools << READ_PAGE_TOOL if document.page_count.positive?

    prompt(
      messages: history + [ { role: "user", content: params[:question] } ],
      tools: tools,
      instructions: instructions_for(document)
    )
  end

  # Tool: the model's only window into the document.
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

  def instructions_for(document)
    scope = +"#{document.chunk_count} passages"
    scope << " across #{document.page_count} pages" if document.page_count.positive?

    status_note =
      if document.indexing?
        "\nThe document is still indexing (#{document.indexed_page_count}/#{document.page_count} pages done). " \
        "search_document only covers indexed pages, but read_page can scan any page on demand."
      else
        ""
      end

    outline_note =
      if document.outline.present?
        "\n\nDocument outline (from its opening pages — use it to pick pages for read_page " \
        "and terms for search_document):\n#{document.outline}"
      else
        ""
      end

    <<~INSTRUCTIONS
      You answer questions about the document "#{document.title}" (#{scope}).#{status_note}

      Rules:
      - You cannot see the document. ALWAYS call search_document (or read_page) before answering.
      - Base your answer ONLY on passages the tool returned in this conversation. If they
        don't contain the answer, search again with different terms; if still not found,
        say the document doesn't appear to cover it.
      - Cite the passage reference (like [§12]) after every claim you take from the
        document. Every factual statement needs at least one citation.
      - Be concise. Do not include your reasoning or the raw passages in the answer.#{outline_note}
    INSTRUCTIONS
  end
end
