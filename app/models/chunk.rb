class Chunk < ApplicationRecord
  belongs_to :document

  validates :content, presence: true
  validates :position, presence: true, uniqueness: { scope: :document_id }

  after_create_commit :index_for_search

  # The citation tag the agent uses, e.g. "§12".
  def reference = "§#{position}"

  private

  def index_for_search
    ActiveRecord::Base.connection.execute(
      ActiveRecord::Base.sanitize_sql_array(
        [ "INSERT INTO chunk_search (content, chunk_id, document_id) VALUES (?, ?, ?)",
          content, id, document_id ]
      )
    )
  end
end
