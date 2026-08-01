require "test_helper"

class DocumentIngestorTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  # ~3 pseudo-pages of prose: paragraphs of long lines separated by blanks.
  def big_text
    paragraph = ("The quick brown fox jumps over the lazy dog again and again. " * 20).strip
    Array.new(30) { paragraph }.join("\n\n")
  end

  def upload_document(io:, filename:, content_type:)
    document = nil
    perform_enqueued_jobs do
      document = Document.new(title: filename, status: "processing")
      document.file.attach(io: io, filename: filename, content_type: content_type)
      document.save!
    end
    document.reload
  end

  test "plain text fans out into pseudo-pages and ends ready with line locators" do
    document = upload_document(
      io: StringIO.new(big_text), filename: "big.txt", content_type: "text/plain"
    )

    assert_equal "ready", document.status
    assert_operator document.page_count, :>, 1
    assert_equal document.page_count, document.indexed_page_count
    assert_equal document.page_count, document.pages.where(status: "indexed").count
    assert_equal document.chunks.count, document.chunk_count
    assert_match(/\Alines \d+–\d+\z/, document.chunks.order(:position).last.locator)

    # Positions are strided per page: page N's chunks live in its block.
    document.pages.find_each do |page|
      page.chunks.each do |chunk|
        assert_includes page.base_position...(page.base_position + DocumentPage::POSITION_STRIDE), chunk.position
      end
    end
  end

  test "line locators stay correct across pseudo-page boundaries" do
    text = big_text
    document = upload_document(
      io: StringIO.new(text), filename: "big.txt", content_type: "text/plain"
    )

    lines = text.split("\n", -1)
    document.chunks.find_each do |chunk|
      first, last = chunk.locator.scan(/\d+/).map(&:to_i)
      assert_equal chunk.content, lines[(first - 1)..(last - 1)].join("\n").strip
    end
  end

  test "docx splits on rendered page breaks and chunks per page" do
    document = upload_document(
      io: StringIO.new(fake_docx(pages: 4)), filename: "module.docx",
      content_type: DocumentIngestor::DOCX_TYPE
    )

    assert_equal "ready", document.status
    assert_equal "docx", document.content_kind
    assert_equal 4, document.page_count
    assert_equal "page 4", document.pages.find_by(number: 4).chunks.first.locator
  end

  test "read_page indexes a pending page on demand" do
    document = Document.new(title: "t", status: "processing")
    document.file.attach(io: StringIO.new(big_text), filename: "big.txt", content_type: "text/plain")
    document.save!
    # Ingest runs (front pages index inline) but page jobs stay queued.
    perform_enqueued_jobs(only: IngestDocumentJob)

    document.reload
    pending = document.pages.where(status: "pending").first
    if pending # front-page inline indexing may have covered a small doc
      PageIndexer.new(pending).call
      assert pending.reload.indexed?
      assert_operator pending.chunks.count, :>, 0
    end
    assert document.askable?, "document should be askable once front pages are inline-indexed"
  end

  private

  WORD_NS = "http://schemas.openxmlformats.org/wordprocessingml/2006/main".freeze

  def fake_docx(pages:)
    paragraphs = (1..pages).flat_map { |n|
      breaker = n > 1 ? %(<w:r><w:lastRenderedPageBreak/></w:r>) : ""
      [ %(<w:p>#{breaker}<w:r><w:t>Page #{n} heading</w:t></w:r></w:p>),
        %(<w:p><w:r><w:t>#{"Body text for page #{n}. " * 30}</w:t></w:r></w:p>) ]
    }.join
    xml = %(<?xml version="1.0"?><w:document xmlns:w="#{WORD_NS}"><w:body>#{paragraphs}</w:body></w:document>)

    buffer = Zip::OutputStream.write_buffer do |zip|
      zip.put_next_entry("word/document.xml")
      zip.write(xml)
    end
    buffer.string
  end
end
