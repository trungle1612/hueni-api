# Đưa đón sân bay (#306): one leg (arrival / departure) a guest asked for with a booking request, cash to the driver.
# It follows its request (declined / expired → cancelled), then its booking (cancelled → cancelled, dates follow).
class Transfer < ApplicationRecord
  KINDS = %w[arrival departure].freeze
  STATUSES = %w[pending done cancelled].freeze

  belongs_to :place
  belongs_to :booking_request, optional: true
  belongs_to :booking, optional: true

  enum :kind, KINDS.index_by(&:itself), validate: true
  enum :status, STATUSES.index_by(&:itself), validate: true
  normalizes :flight, with: ->(value) { value.strip.upcase.presence }

  # Full sentences: the guest sees them as they are (Place#transfer_legs), with no attribute names to translate.
  validates :date, presence: { message: "Thiếu ngày đưa đón" }
  validates :pickup_time, format: { with: /\A([01]\d|2[0-3]):[0-5]\d\z/, message: "Giờ máy bay đến phải theo dạng 14:30" }, allow_nil: true
  validates :pickup_time, presence: { message: "Cần giờ máy bay đến để đón đúng giờ" }, if: :arrival?
  validates :flight, length: { maximum: 20, message: "Số hiệu chuyến bay tối đa 20 ký tự" }
  validates :price, numericality: { greater_than_or_equal_to: 0, only_integer: true }

  # Đã đón / Đã đưa (#307): the driver took the guest and the cash. Only a leg still waiting, once its booking exists.
  def finish
    return update!(status: "done") if pending? && booking_id
    errors.add(:base, cancelled? ? "Chuyến đưa đón này đã huỷ" : done? ? "Chuyến đưa đón này đã xong" : "Nhận yêu cầu đặt phòng trước")
    false
  end
end
