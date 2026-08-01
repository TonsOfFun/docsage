class CreateDocumentPages < ActiveRecord::Migration[8.1]
  def change
    create_table :document_pages do |t|
      t.references :document, null: false, foreign_key: true
      t.integer :number, null: false
      t.string :status, null: false, default: "pending"
      # Page text captured during planning (text/docx). Nil for PDFs — the
      # page job extracts its own page so extraction parallelizes too.
      t.text :content
      # For text files: the source line this pseudo-page starts on, so chunk
      # locators stay real "lines X–Y" references into the original file.
      t.integer :start_line
      t.integer :chunk_count, null: false, default: 0
      t.string :error_message
      t.timestamps
    end
    add_index :document_pages, [ :document_id, :number ], unique: true

    add_column :documents, :page_count, :integer, null: false, default: 0
    add_column :documents, :indexed_page_count, :integer, null: false, default: 0

    add_reference :chunks, :document_page, foreign_key: true
  end
end
