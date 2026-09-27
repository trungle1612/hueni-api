class Room < ApplicationRecord
  belongs_to :place
  has_many :bookings

  validates :name, presence: true, uniqueness: { scope: :place_id }
  validates :max_guests, numericality: { only_integer: true, greater_than: 0 }
end
