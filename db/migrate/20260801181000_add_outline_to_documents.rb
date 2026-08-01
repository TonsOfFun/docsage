class AddOutlineToDocuments < ActiveRecord::Migration[8.1]
  def change
    # Front-matter/TOC text captured from the document's opening pages during
    # ingestion; given to the agent as a map of the document.
    add_column :documents, :outline, :text
  end
end
