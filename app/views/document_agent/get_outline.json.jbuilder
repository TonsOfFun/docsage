# Tool schema for DocumentAgent#get_outline (common tools format).
json.name "get_outline"
json.description "Get the document's outline — its table of contents and front matter, " \
                 "captured from the opening pages at ingest. Use it to see what the " \
                 "document covers, pick page numbers for read_page, and choose search " \
                 "terms for search_document."
json.parameters do
  json.type "object"
  json.properties { }
  json.required []
end
