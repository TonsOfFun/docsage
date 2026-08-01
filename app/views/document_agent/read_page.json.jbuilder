# Tool schema for DocumentAgent#read_page (common tools format).
json.name "read_page"
json.description "Read the full text of one page of the document by page number. " \
                 "If that page hasn't been indexed yet it is scanned on demand, so this " \
                 "works even while the document is still indexing. Use it to follow the " \
                 "document's outline or a citation to a specific page."
json.parameters do
  json.type "object"
  json.properties do
    json.number do
      json.type "integer"
      json.description "1-based page number to read"
    end
  end
  json.required [ "number" ]
end
