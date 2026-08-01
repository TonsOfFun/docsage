# Phase 1 of ingestion: plan an uploaded file into DocumentPage records and
# fan out one IndexDocumentPageJob per page, so a 200-page document indexes
# concurrently instead of in series — and becomes askable as soon as the
# first pages land.
#
# Page boundaries are real pages for PDFs (count only — each page job
# extracts its own page so the expensive parsing parallelizes too) and DOCX
# (split on Word's rendered page breaks), and size-based pseudo-pages for
# plain text (with a start_line so chunk locators stay real line numbers).
#
# Each page owns a fixed block of §N positions (DocumentPage::POSITION_STRIDE),
# so citations are stable and in document order no matter what order the
# page jobs finish in.
class DocumentIngestor
  # Target size of a plain-text pseudo-page (~8 chunks each).
  PAGE_TARGET_CHARS = 12_000

  TEXT_KINDS = %w[text/plain text/markdown].freeze
  DOCX_TYPE = "application/vnd.openxmlformats-officedocument.wordprocessingml.document".freeze

  def initialize(document)
    @document = document
  end

  def call
    blob = @document.file.blob
    @document.update!(content_kind: kind_for(blob), byte_size: blob.byte_size)

    pages = plan(blob)
    if pages.empty?
      @document.update!(status: "ready", chunk_count: 0)
      return
    end

    records = @document.transaction do
      created = pages.map { |attrs| @document.pages.create!(attrs.merge(status: "pending")) }
      @document.update!(status: "indexing", page_count: created.size, indexed_page_count: 0)
      created
    end

    index_front_pages!(records)
    records.reject(&:indexed?).each { |page| IndexDocumentPageJob.perform_later(page.id) }
  rescue StandardError => e
    @document.update!(status: "failed", error_message: "#{e.class}: #{e.message}".truncate(250))
    raise
  end

  # The document is askable the moment ingestion returns: index the first
  # FRONT_PAGES_MIN pages inline, then keep going one page at a time while
  # the content still reads as front matter / table of contents (up to
  # FRONT_PAGES_MAX). Those outline pages are saved on the document and fed
  # to the agent as a map of the rest of the doc.
  FRONT_PAGES_MIN = 3
  FRONT_PAGES_MAX = 8

  private

  def index_front_pages!(records)
    outline_pages = []

    records.first(FRONT_PAGES_MAX).each_with_index do |page, index|
      break if index >= FRONT_PAGES_MIN && !outline_like?(records[index - 1])

      PageIndexer.new(page).call
      outline_pages << page if outline_like?(page)
    end

    outline = outline_pages.flat_map { |page| page.chunks.order(:position).pluck(:content) }.join("\n\n")
    @document.update!(outline: outline.truncate(6_000)) if outline.present?
  end

  # Heuristic: front matter and TOCs are mostly short lines, dotted/numbered
  # leaders, and "Contents"-style headings — body prose is long lines.
  def outline_like?(page)
    text = page.chunks.order(:position).pluck(:content).join("\n")
    return false if text.blank?
    return true if text.match?(/table of contents|^\s*contents\s*$/i)

    lines = text.split("\n").map(&:strip).reject(&:blank?)
    return false if lines.empty?

    short = lines.count { |line| line.length < 60 }
    leaders = lines.count { |line| line.match?(/(\.{3,}|\t+)\s*\d+\s*$|^\d+(-\d+)?\s*$/) }
    short.fdiv(lines.size) > 0.7 || leaders.fdiv(lines.size) > 0.3
  end

  def kind_for(blob)
    extension = blob.filename.extension_without_delimiter
    return "pdf" if blob.content_type == "application/pdf" || extension == "pdf"
    return "docx" if blob.content_type == DOCX_TYPE || extension == "docx"

    "text"
  end

  def plan(blob)
    case @document.content_kind
    when "pdf" then plan_pdf(blob)
    when "docx" then plan_docx(blob)
    else plan_text(blob.download.force_encoding(Encoding::UTF_8).scrub)
    end
  end

  # PDF pages are planned by count only; extracting text is the slow part,
  # so each page job does its own extraction in parallel.
  def plan_pdf(blob)
    require "pdf-reader"

    count = blob.open { |io| PDF::Reader.new(io.path).page_count }
    (1..count).map { |number| { number: number } }
  end

  def plan_docx(blob)
    texts = blob.open { |io| DocxExtractor.new(io.path).page_texts }
    texts.each_with_index.map { |text, index| { number: index + 1, content: text } }
  end

  # Group lines into pseudo-pages on paragraph boundaries, remembering each
  # page's first line so chunks can keep "lines X–Y" locators.
  def plan_text(text)
    lines = text.split("\n", -1)
    pages = []
    buffer = []
    buffer_start = 1
    size = 0

    flush = lambda do |next_line|
      content = buffer.join("\n")
      pages << { number: pages.size + 1, content: content, start_line: buffer_start } if content.strip.present?
      buffer = []
      buffer_start = next_line
      size = 0
    end

    lines.each_with_index do |line, index|
      buffer << line
      size += line.length + 1
      flush.call(index + 2) if size >= PAGE_TARGET_CHARS && line.blank?
    end
    flush.call(lines.size + 1)
    pages
  end
end
