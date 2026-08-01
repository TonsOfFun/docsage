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

    prompt(
      messages: history + [ { role: "user", content: params[:question] } ],
      tools: [ SEARCH_TOOL ],
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

  private

  def document
    params[:document]
  end

  def instructions_for(document)
    <<~INSTRUCTIONS
      You answer questions about the document "#{document.title}" (#{document.chunk_count} passages).

      Rules:
      - You cannot see the document. ALWAYS call search_document before answering.
      - Base your answer ONLY on passages the tool returned in this conversation. If they
        don't contain the answer, search again with different terms; if still not found,
        say the document doesn't appear to cover it.
      - Cite the passage reference (like [§12]) after every claim you take from the
        document. Every factual statement needs at least one citation.
      - Be concise. Do not include your reasoning or the raw passages in the answer.
    INSTRUCTIONS
  end
end
