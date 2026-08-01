class CreateChunkSearchIndex < ActiveRecord::Migration[8.1]
  # SQLite FTS5 full-text index over chunk content. Chunks are written once at
  # ingest, so the index is populated alongside the row — no triggers needed.
  def up
    execute <<~SQL
      CREATE VIRTUAL TABLE chunk_search USING fts5(
        content,
        chunk_id UNINDEXED,
        document_id UNINDEXED,
        tokenize = 'porter unicode61'
      );
    SQL
  end

  def down
    execute "DROP TABLE chunk_search;"
  end
end
