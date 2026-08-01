class CreateChunks < ActiveRecord::Migration[8.1]
  def change
    create_table :chunks do |t|
      t.references :document, null: false, foreign_key: true
      t.integer :position
      t.text :content
      t.string :locator

      t.timestamps
    end
  end
end
