# Thanh toán (#139): money the guest paid (payment) or got back (refund) for a direct booking.
# Never edited; a wrong one is deleted by an owner. Both are logged.
class Payment < ApplicationRecord
  include VndPrice

  belongs_to :booking
  belongs_to :user, optional: true
  has_paper_trail on: %i[create destroy], meta: { place_id: ->(payment) { payment.booking.room.place_id }, room_id: ->(payment) { payment.booking.room_id } }

  METHODS = { "cash" => "Tiền mặt", "bank" => "Chuyển khoản", "card" => "Thẻ" }.freeze
  enum :kind, { payment: "payment", refund: "refund" }, validate: true
  enum :payment_method, METHODS.keys.index_with(&:itself), validate: true

  vnd_price :amount
  validates :amount, presence: true, numericality: { greater_than: 0 }
  normalizes :note, with: ->(value) { value.strip.presence }
  validates :note, length: { maximum: 200 }
  validate :within_balance, on: :create
  # Trang đặt phòng riêng (#172): money in ends an online booking's hold.
  after_create { booking.update_columns(hold_expires_at: nil) if payment? && booking.hold_expires_at }

  def signed_amount = refund? ? -amount : amount
  def method_label = METHODS[payment_method]

  private
    # Never more than is due, never refund more than was paid.
    def within_balance
      return unless booking && amount.is_a?(Integer) && amount.positive?
      if booking.ical? then errors.add(:base, "Đặt phòng OTA thanh toán qua kênh OTA")
      elsif refund? then errors.add(:amount, "không được lớn hơn số đã thu (#{VndPrice.format(booking.paid)})") if amount > booking.paid
      elsif booking.cancelled? then errors.add(:base, "Đặt phòng đã huỷ, chỉ hoàn tiền được")
      elsif (due = booking.due) && amount > due then errors.add(:amount, "không được lớn hơn số còn phải thu (#{VndPrice.format(due)})")
      end
    end
end
