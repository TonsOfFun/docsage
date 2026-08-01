class QuestionsController < ApplicationController
  def create
    document = Document.find(params[:document_id])
    question = params.require(:question).to_s.strip

    if question.blank? || !document.ready?
      return redirect_to document, alert: "Type a question once the document is ready."
    end

    # solid_agent's auto_save persists the whole exchange — user turn, tool
    # calls/results, and the generation with tokens and provenance.
    DocumentAgent.with(document: document, question: question).answer.generate_now

    redirect_to document
  rescue StandardError => e
    Rails.logger.error("[DocumentAgent] #{e.class}: #{e.message}")
    redirect_to document, alert: "The agent hit an error: #{e.message.truncate(160)}"
  end
end
