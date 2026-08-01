# Turns an uploaded file into searchable, citable chunks.
#
# Text-ish files chunk on paragraph boundaries with line-number locators;
# PDFs chunk per run of pages with page-number locators. Either way each
# chunk gets a stable position (its §N citation tag) and a human-readable
# locator shown alongside citations.
class DocumentIngestor
  TARGET_CHUNK_CHARS = 1500
  TEXT_KINDS = %w[text/plain text/markdown].freeze

  def initialize(document)
    @document = document
  end

  def call
    pieces = extract
    @document.transaction do
      pieces.each_with_index do |piece, index|
        @document.chunks.create!(position: index + 1, content: piece[:content], locator: piece[:locator])
      end
      @document.update!(status: "ready", chunk_count: pieces.size)
    end
  rescue StandardError => e
    @document.update!(status: "failed", error_message: "#{e.class}: #{e.message}".truncate(250))
    raise
  end

  private

  def extract
    blob = @document.file.blob
    @document.update!(content_kind: kind_for(blob), byte_size: blob.byte_size)

    case kind_for(blob)
    when "pdf" then chunk_pdf(blob)
    else chunk_text(blob.download.force_encoding(Encoding::UTF_8).scrub)
    end
  end

  def kind_for(blob)
    return "pdf" if blob.content_type == "application/pdf" || blob.filename.extension_without_delimiter == "pdf"

    "text"
  end

  # Paragraph-boundary chunking with line locators, so a citation like
  # "§12 · lines 340–361" points at real lines in the source file.
  def chunk_text(text)
    lines = text.split("\n", -1)
    pieces = []
    buffer = []
    buffer_start = 1
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
      flush.call(index + 2) if size >= TARGET_CHUNK_CHARS && line.blank?
    end
    flush.call(lines.size + 1)
    pieces
  end

  def chunk_pdf(blob)
    require "pdf-reader"

    pieces = []
    blob.open do |io|
      reader = PDF::Reader.new(io.path)
      reader.pages.each_with_index do |page, index|
        text = page.text.to_s.strip
        next if text.blank?

        split_evenly(text).each do |part|
          pieces << { content: part, locator: "page #{index + 1}" }
        end
      end
    end
    pieces
  end

  # A dense PDF page can exceed the chunk target; split it on paragraph
  # boundaries while keeping the page locator.
  def split_evenly(text)
    return [ text ] if text.length <= TARGET_CHUNK_CHARS * 2

    text.split(/\n{2,}/).each_with_object([ +"" ]) do |paragraph, parts|
      if parts.last.length + paragraph.length > TARGET_CHUNK_CHARS * 2 && parts.last.present?
        parts << +""
      end
      parts.last << paragraph << "\n\n"
    end.map(&:strip).reject(&:blank?)
  end
end
