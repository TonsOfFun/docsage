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
    @context = @document.agent_contexts.find_by(agent_name: "DocumentAgent")
    @messages = @context&.messages&.order(:created_at) || []
    @chunks_by_position = @document.chunks.index_by(&:position)
  end
end
