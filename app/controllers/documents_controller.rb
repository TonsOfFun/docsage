class DocumentsController < ApplicationController
  def index
    @documents = Document.order(created_at: :desc)
  end

  def create
    file = params.require(:document)[:file]
    document = Document.new(
      title: params[:document][:title].presence || file&.original_filename || "Untitled",
      status: "processing"
    )
    document.file.attach(file) if file

    if file && document.save
      redirect_to document, notice: "Uploaded — extracting and indexing…"
    else
      redirect_to root_path, alert: document.errors.full_messages.to_sentence.presence || "Choose a file to upload."
    end
  end

  def show
    @document = Document.find(params[:id])
    # One card per exchange: each ask creates its own context (run/session),
    # newest first.
    @exchanges = @document.agent_contexts
      .where(agent_name: "DocumentAgent")
      .includes(:messages, :generations)
      .order(created_at: :desc)
    @total_tokens = @exchanges.sum { |c| c.total_input_tokens.to_i + c.total_output_tokens.to_i }
    @chunks_by_position = @document.chunks.index_by(&:position)
    @instructions_preview = instructions_preview
  end

  private

  # The system prompt exactly as the agent's view template renders it right
  # now (Generation exposes the framework's instructions resolution).
  def instructions_preview
    return unless @document.askable?

    DocumentAgent.with(document: @document, question: "").answer.instructions
  rescue StandardError => e
    Rails.logger.warn("[DocumentsController] instructions preview failed: #{e.message}")
    nil
  end
end
