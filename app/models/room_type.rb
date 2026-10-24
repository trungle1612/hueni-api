# Loại phòng (#138): the homestay's own list; rooms pick one. Calendar filter now, Rates / Báo cáo later.
class RoomType < ApplicationRecord
  belongs_to :place
  has_many :rooms, dependent: :restrict_with_error

  normalizes :name, with: ->(value) { value.squish }
  validates :name, presence: true, length: { maximum: 50 }, uniqueness: { scope: :place_id, case_sensitive: false }
end
