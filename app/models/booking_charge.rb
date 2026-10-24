# A service on a booking's bill (#140): name, price and unit copied from the catalog when added.
class BookingCharge < ApplicationRecord
  belongs_to :booking
  belongs_to :user, optional: true
  has_paper_trail on: %i[create destroy], meta: { place_id: ->(charge) { charge.booking.room.place_id }, room_id: ->(charge) { charge.booking.room_id } }

  validates :quantity, numericality: { only_integer: true, in: 1..999 }
  validate -> { errors.add(:base, "Đặt phòng đã huỷ") if booking&.cancelled? }, on: :create

  def amount = unit_price * quantity
  def label = "#{name} × #{quantity}#{" #{unit}" if unit}"
end
