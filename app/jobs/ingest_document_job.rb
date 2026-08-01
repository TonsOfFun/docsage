class IngestDocumentJob < ApplicationJob
  queue_as :default

  def perform(document_id)
    document = Document.find(document_id)
    return if document.ready?

    DocumentIngestor.new(document).call
  end
end
