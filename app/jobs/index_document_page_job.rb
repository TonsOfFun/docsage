class IndexDocumentPageJob < ApplicationJob
  queue_as :default

  def perform(document_page_id)
    page = DocumentPage.find(document_page_id)
    PageIndexer.new(page).call
  end
end
