# Tool schema for DocumentAgent#search_document (common tools format).
json.name "search_document"
json.description "Full-text search this document. Returns the most relevant passages, " \
                 "each tagged with a citation reference like §12. Call it before answering; " \
                 "call it again with different terms if the first results don't answer the question."
json.parameters do
  json.type "object"
  json.properties do
    json.query do
      json.type "string"
      json.description "Search terms — significant words from the question, or synonyms on retry"
    end
  end
  json.required [ "query" ]
end
