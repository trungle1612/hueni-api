# Chốt ca và bàn giao (#167). expected is the app's figure at closing (Shift#expected); a difference needs a note
# and shows on the owner's Hôm nay that day and in Hoạt động. keep stays in the till for the next shift.
class ShiftClose < ApplicationRecord
  include VndPrice

  DENOMINATIONS = [ 500_000, 200_000, 100_000, 50_000, 20_000, 10_000 ].freeze

  belongs_to :place
  belongs_to :user, optional: true
  belongs_to :handed_to, class_name: "User", optional: true
  has_paper_trail on: %i[create], meta: { place_id: :place_id }

  vnd_price :counted, :keep
  normalizes :note, with: ->(value) { value.squish.presence }
  validates :counted, :keep, presence: true
  validates :note, length: { maximum: 500 }
  validates :note, presence: { message: "cần ghi lý do khi tiền đếm lệch với app" }, if: :difference?
  validate -> { errors.add(:keep, "không được lớn hơn số đếm được (#{VndPrice.format(counted)})") }, if: -> { counted.is_a?(Integer) && keep.is_a?(Integer) && keep > counted }
  validate -> { errors.add(:handed_to, "phải là thành viên của homestay") unless place.users.exists?(handed_to_id) }, if: :handed_to_id

  scope :with_difference, -> { where("counted <> expected") }

  # Thiếu < 0 < Thừa.
  def difference = counted.is_a?(Integer) ? counted - expected : 0
  def difference? = !difference.zero?
end
