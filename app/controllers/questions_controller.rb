class QuestionsController < ApplicationController
  def create
    document = Document.find(params[:document_id])
    question = params.require(:question).to_s.strip

    if question.blank? || !document.askable?
      return redirect_to document, alert: "Type a question once the document is ready."
    end

    # solid_agent's auto_save persists the whole exchange — user turn, tool
    # calls/results, and the generation with tokens and provenance.
    generation = DocumentAgent.with(document: document, question: question).answer
    response = generation.generate_now
    verify_citations!(document, generation.send(:agent).context, response)

    redirect_to document
  rescue StandardError => e
    Rails.logger.error("[DocumentAgent] #{e.class}: #{e.message}")
    redirect_to document, alert: "The agent hit an error: #{e.message.truncate(160)}"
  end

  private

  # Deterministic citation check: every §N in the answer must have been
  # served by a tool during the run. If any weren't, give the agent ONE
  # corrective pass (continuing the same context, so it sees its answer and
  # what the tools actually returned), then record the final verdict on the
  # context for the UI to flag.
  def verify_citations!(document, context, response)
    return if context.nil?

    check = CitationValidator.call(
      content: response.message&.content,
      served_positions: context.reload.options&.dig("served_positions")
    )

    corrected_pass = false
    if check.unverified.any?
      refs = check.unverified.map { |position| "§#{position}" }.join(", ")
      correction = "Citation check failed: #{refs} did not appear in any tool result this run. " \
                   "Re-verify with your tools and give a corrected answer using only verified citations."
      corrected = DocumentAgent.with(document: document, question: correction, context_id: context.id)
                               .answer.generate_now
      corrected_pass = true
      check = CitationValidator.call(
        content: corrected.message&.content,
        served_positions: context.reload.options&.dig("served_positions")
      )
    end

    context.update_columns(
      options: (context.reload.options || {}).merge(
        "citation_check" => check.to_h.merge("corrected" => corrected_pass)
      )
    )
  rescue StandardError => e
    Rails.logger.warn("[CitationCheck] #{e.class}: #{e.message}")
  end
end
