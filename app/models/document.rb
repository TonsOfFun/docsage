class Document < ApplicationRecord
  has_one_attached :file
  has_many :chunks, dependent: :destroy
  has_many :pages, class_name: "DocumentPage", dependent: :destroy
  has_many :agent_contexts, as: :contextable, dependent: :destroy

  # processing → planning pages; indexing → page jobs running (partially
  # searchable); ready → every page indexed.
  STATUSES = %w[processing indexing ready failed].freeze

  validates :title, presence: true
  validates :status, inclusion: { in: STATUSES }

  after_create_commit -> { IngestDocumentJob.perform_later(id) }

  def ready? = status == "ready"
  def failed? = status == "failed"
  def indexing? = status == "indexing"

  # Questions are allowed as soon as any page is searchable — answers just
  # come from the indexed portion until the rest lands.
  def askable? = ready? || (indexing? && indexed_page_count.positive?)

  # FTS5 search over this document's chunks, best matches first.
  def search_chunks(query, limit: 5)
    terms = sanitized_fts_query(query)
    return Chunk.none if terms.blank?

    rows = ActiveRecord::Base.connection.select_all(
      ActiveRecord::Base.sanitize_sql_array([ <<~SQL, terms, id, limit ])
        SELECT chunk_id, rank FROM chunk_search
        WHERE chunk_search MATCH ? AND document_id = ?
        ORDER BY rank LIMIT ?
      SQL
    )
    ids = rows.map { |row| row["chunk_id"] }
    chunks.where(id: ids).in_order_of(:id, ids)
  end

  private

  # FTS5 has its own query syntax; user text goes in as quoted OR'd terms so
  # stray punctuation can't produce a syntax error.
  def sanitized_fts_query(query)
    query.to_s.scan(/[[:alnum:]]+/).map { |term| %("#{term}") }.join(" OR ")
  end
end
