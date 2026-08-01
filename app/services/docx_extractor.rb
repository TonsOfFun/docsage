# Pulls page texts out of a .docx (a zip whose body is word/document.xml).
#
# Word saves <w:lastRenderedPageBreak/> markers where its layout engine broke
# pages, plus explicit <w:br w:type="page"/> breaks — split on those so page
# numbers line up with what the client sees in Word. Documents saved without
# rendered breaks fall back to size-based pseudo-pages.
class DocxExtractor
  WORD_NS = { "w" => "http://schemas.openxmlformats.org/wordprocessingml/2006/main" }.freeze
  FALLBACK_PAGE_CHARS = DocumentIngestor::PAGE_TARGET_CHARS

  def initialize(path)
    @path = path
  end

  def page_texts
    xml = Zip::File.open(@path) { |zip| zip.read("word/document.xml") }
    doc = Nokogiri::XML(xml)

    pages = [ [] ]
    doc.xpath("//w:body//w:p", WORD_NS).each do |paragraph|
      breaks = paragraph.xpath(".//w:lastRenderedPageBreak | .//w:br[@w:type='page']", WORD_NS)
      pages << [] if breaks.any? && pages.last.any?

      text = paragraph.xpath(".//w:t", WORD_NS).map(&:text).join
      pages.last << text if text.present?
    end

    texts = pages.map { |paragraphs| paragraphs.join("\n\n") }.reject(&:blank?)
    texts.size <= 1 ? split_by_size(texts.join("\n\n")) : texts
  end

  private

  def split_by_size(text)
    return [] if text.blank?

    text.split(/\n{2,}/).each_with_object([ +"" ]) do |paragraph, parts|
      parts << +"" if parts.last.length + paragraph.length > FALLBACK_PAGE_CHARS && parts.last.present?
      parts.last << paragraph << "\n\n"
    end.map(&:strip).reject(&:blank?)
  end
end
