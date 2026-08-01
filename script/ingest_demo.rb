# Ingest any local document through the page fan-out pipeline and watch it
# index, printing when it became askable and how long the full index took.
#
# Run: bin/rails runner script/ingest_demo.rb path/to/file.docx
path = ARGV[0] or abort "usage: bin/rails runner script/ingest_demo.rb <file>"
started = Time.current

content_type = {
  ".pdf" => "application/pdf",
  ".docx" => DocumentIngestor::DOCX_TYPE,
  ".md" => "text/markdown"
}.fetch(File.extname(path).downcase, "text/plain")

document = Document.new(title: File.basename(path, ".*").tr("_-", " "), status: "processing")
document.file.attach(io: File.open(path), filename: File.basename(path), content_type: content_type)
document.save!
puts "created document #{document.id}; waiting for ingest…"

askable_at = nil
240.times do
  document.reload
  askable_at ||= Time.current if document.askable?
  print "\r  status=#{document.status} pages=#{document.indexed_page_count}/#{document.page_count} chunks=#{document.chunk_count}   "
  break if document.ready? || document.failed?
  sleep 0.5
end
puts

document.reload
puts "final:    #{document.status} — #{document.page_count} pages, #{document.chunk_count} chunks"
puts "askable:  after #{(askable_at - started).round(2)}s (front pages inline)" if askable_at
puts "total:    #{(Time.current - started).round(2)}s"
puts "outline:  #{document.outline ? "#{document.outline.length} chars captured" : 'none'}"
puts "sample chunk locators: #{document.chunks.order(:position).limit(3).pluck(:locator).join(', ')} … #{document.chunks.order(:position).last&.locator}"
