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

  validates :pickup_time, format: { with: /\A([01]\d|2[0-3]):[0-5]\d\z/, message: "phải theo dạng 14:30" }, allow_nil: true
  validates :pickup_time, presence: { message: "cần giờ máy bay đến" }, if: :arrival?
  validates :flight, length: { maximum: 20 }
  validates :price, numericality: { greater_than_or_equal_to: 0, only_integer: true }
end
