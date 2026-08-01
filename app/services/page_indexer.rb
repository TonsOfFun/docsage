# Phase 2 of ingestion: turn one DocumentPage into searchable chunks.
# Runs concurrently across pages (IndexDocumentPageJob), inline for the
# document's opening pages, and on demand when the agent asks to read a page
# that hasn't been indexed yet.
#
# Chunk positions come from the page's reserved block (base_position + i),
# so §N citations are stable regardless of job completion order.
class PageIndexer
  TARGET_CHUNK_CHARS = 1500

  def initialize(page)
    @page = page
    @document = page.document
  end

  def call
    return if @page.indexed?

    @page.update!(status: "processing")
    pieces = clamp(build_pieces)

    @page.transaction do
      pieces.each_with_index do |piece, index|
        @document.chunks.create!(
          document_page: @page,
          position: @page.base_position + index,
          content: piece[:content],
          locator: piece[:locator]
        )
      end
      @page.update!(status: "indexed", chunk_count: pieces.size)
    end
    finalize_document!
  rescue StandardError => e
    message = "#{e.class}: #{e.message}".truncate(250)
    @page.update!(status: "failed", error_message: message)
    @document.update!(status: "failed", error_message: "page #{@page.number}: #{message}".truncate(250)) unless @document.ready?
    raise
  end

  private

  def build_pieces
    if @page.start_line.present?
      chunk_text(@page.content.to_s, first_line: @page.start_line)
    else
      text = @page.content.presence || extract_pdf_page
      split_evenly(text.to_s.strip).map { |part| { content: part, locator: "page #{@page.number}" } }
    end
  end

  def extract_pdf_page
    require "pdf-reader"

    @document.file.blob.open { |io| PDF::Reader.new(io.path).page(@page.number).text }
  end

  # Every page reserves POSITION_STRIDE positions; an absurdly dense page
  # merges its overflow into the last chunk rather than colliding with the
  # next page's block.
  def clamp(pieces)
    limit = DocumentPage::POSITION_STRIDE
    return pieces if pieces.size <= limit

    head, overflow = pieces[0...limit - 1], pieces[(limit - 1)..]
    head + [ overflow.first.merge(content: overflow.map { |piece| piece[:content] }.join("\n\n")) ]
  end

  # Paragraph-boundary chunking with real line-number locators, offset by the
  # pseudo-page's position in the original file.
  def chunk_text(text, first_line:)
    lines = text.split("\n", -1)
    pieces = []
    buffer = []
    buffer_start = first_line
    size = 0

    flush = lambda do |next_line|
      content = buffer.join("\n").strip
      pieces << { content: content, locator: "lines #{buffer_start}–#{next_line - 1}" } if content.present?
      buffer = []
      buffer_start = next_line
      size = 0
    end

    lines.each_with_index do |line, index|
      buffer << line
      size += line.length + 1
      flush.call(first_line + index + 1) if size >= TARGET_CHUNK_CHARS && line.blank?
    end
    flush.call(first_line + lines.size)
    pieces
  end

  # A dense page can exceed the chunk target; split it on paragraph
  # boundaries while keeping the page locator.
  def split_evenly(text)
    return [ text ].reject(&:blank?) if text.length <= TARGET_CHUNK_CHARS * 2

    text.split(/\n{2,}/).each_with_object([ +"" ]) do |paragraph, parts|
      if parts.last.length + paragraph.length > TARGET_CHUNK_CHARS * 2 && parts.last.present?
        parts << +""
      end
      parts.last << paragraph << "\n\n"
    end.map(&:strip).reject(&:blank?)
  end

  # Atomic progress bump; the job that completes the final page flips the
  # document to ready. chunk_count updates live so the UI shows progress.
  def finalize_document!
    Document.where(id: @document.id).update_all("indexed_page_count = indexed_page_count + 1")
    @document.reload
    attrs = { chunk_count: @document.chunks.count }
    attrs[:status] = "ready" if @document.indexed_page_count >= @document.page_count && !@document.failed?
    @document.update!(attrs)
  end
end
