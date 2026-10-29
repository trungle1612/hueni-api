# Chờ duyệt (#168): a refund asked by staff without the refund right. The owner approves it (the refund is written
# then, as the requester's) or rejects it. Both are logged.
class RefundRequest < ApplicationRecord
  include VndPrice

  belongs_to :booking
  belongs_to :requested_by, class_name: "User", optional: true
  belongs_to :decided_by, class_name: "User", optional: true
  belongs_to :payment, optional: true
  has_paper_trail meta: { place_id: ->(request) { request.booking.room.place_id }, room_id: ->(request) { request.booking.room_id } }

  enum :status, { pending: "pending", approved: "approved", rejected: "rejected" }, validate: true
  enum :payment_method, Payment::METHODS.keys.index_with(&:itself), validate: true

  vnd_price :amount
  validates :amount, presence: true, numericality: { greater_than: 0 }
  normalizes :note, with: ->(value) { value.squish.presence }
  validates :note, length: { maximum: 200 }
  validate :within_paid, on: :create

  def approve(user)
    return refuse("Yêu cầu đã được xử lý") unless pending?
    transaction do
      refund = booking.payments.create(kind: "refund", amount:, payment_method:, note: note || "Hoàn tiền (đã duyệt)", user: requested_by)
      unless refund.persisted?
        refuse(refund.errors.full_messages.to_sentence)
        raise ActiveRecord::Rollback
      end
      update!(status: "approved", payment: refund, decided_by: user, decided_at: Time.current)
    end || false
  end

  def reject(user)
    return refuse("Yêu cầu đã được xử lý") unless pending?
    update(status: "rejected", decided_by: user, decided_at: Time.current)
  end

  private
    def within_paid
      return unless booking && amount.is_a?(Integer)
      if booking.ical? then errors.add(:base, "Đặt phòng OTA thanh toán qua kênh OTA")
      elsif amount > booking.paid then errors.add(:amount, "không được lớn hơn số đã thu (#{VndPrice.format(booking.paid)})")
      end
    end

    def refuse(reason)
      errors.add(:base, reason)
      false
    end
end
