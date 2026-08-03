# Tool schema for DocumentAgent#get_document_stats (common tools format).
json.name "get_document_stats"
json.description "Get the document's size and structure: page count, passage (chunk) count, " \
                 "file size, format, indexing status, and how §N citation tags map to pages. " \
                 "Use it for questions about the document's length or size, and to convert a " \
                 "§N reference into a page number."
json.parameters do
  json.type "object"
  json.properties { }
  json.required []
end
