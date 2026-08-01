class CreateDocuments < ActiveRecord::Migration[8.1]
  def change
    create_table :documents do |t|
      t.string :title
      t.string :status
      t.string :content_kind
      t.integer :byte_size
      t.integer :chunk_count
      t.string :error_message

      t.timestamps
    end
  end
end
