# One page (real for PDF/DOCX, size-based pseudo-page for plain text) of an
# uploaded document. Pages are planned up front by DocumentIngestor, then
# indexed concurrently — each page owns a block of chunk positions so §N
# citations are stable no matter what order the jobs finish in.
class DocumentPage < ApplicationRecord
  # How many §N positions each page reserves. Pages produce a handful of
  # chunks (~1.5k chars each), so 100 leaves generous headroom.
  POSITION_STRIDE = 100

  STATUSES = %w[pending processing indexed failed].freeze

  belongs_to :document
  has_many :chunks, dependent: :destroy

  validates :number, presence: true, uniqueness: { scope: :document_id }
  validates :status, inclusion: { in: STATUSES }

  def indexed? = status == "indexed"

  # First §N position this page's chunks occupy.
  def base_position = (number - 1) * POSITION_STRIDE + 1
end
