# Đặt phòng theo đoàn (#164): several rooms, one contact. Each room is a normal booking with group_id, so it shows
# everywhere (Hôm nay, Lịch, Báo cáo) and keeps every booking rule. The group discount is frozen into each booking's
# Giảm giá when the room is added, so total / due / Report need nothing new.
class Group < ApplicationRecord
  belongs_to :place
  has_many :bookings
  has_paper_trail on: %i[create update], only: %i[number name contact phone origin discount_pct bill], meta: { place_id: :place_id }

  enum :bill, { one: "one", split: "split" }, prefix: true, validate: true
  ORIGINS = [ "Công ty lữ hành", "Điện thoại / Zalo", "Trực tiếp" ].freeze

  normalizes :name, :contact, :phone, :origin, with: ->(value) { value.squish.presence }
  validates :name, presence: true, length: { maximum: 100 }
  validates :contact, :origin, length: { maximum: 100 }
  validates :phone, length: { maximum: 20 }
  validates :discount_pct, numericality: { only_integer: true, in: 0..100 }

  before_create { self.number = place.next_group_number! }

  def code = number && format("DOAN-%04d", number)

  # Every room in the group, cancelled ones (Bỏ khỏi đoàn) excluded.
  def rooms_booked = bookings.confirmed.includes(:room, :charges, :payments).sort_by { [ it.room.name, it.id ] }

  # What the leader pays: every room on one bill, minus Khách tự trả; on split bills, every room.
  def billed = rooms_booked.reject { bill_one? && it.pays_own? }

  # Creates the group with one booking per room, all or nothing: a room that can't be booked fails the whole group,
  # its reason under errors[:base] as "Phòng X: …".
  def book(rooms, start_date:, end_date:)
    errors.add(:base, "Chọn ít nhất 2 phòng (một phòng thì đặt phòng thường)") if rooms.size < 2
    return false if errors.any? || invalid?
    transaction do
      save!
      rooms.all? { add_room(it, start_date:, end_date:) } || raise(ActiveRecord::Rollback)
    end || false
  end

  # + Thêm phòng: a normal booking under the group's name at the group price. False with errors[:base] if refused.
  def add_room(room, start_date:, end_date:)
    booking = bookings.build(room:, start_date:, end_date:, guest_name: name, guest_phone: phone, guests: room.max_guests)
    booking.assign_attributes(discount_input: "#{discount_pct}%", discount_reason: "Giá đoàn #{code}") if discount_pct.positive?
    return true if booking.save
    errors.add(:base, "Phòng #{room.name}: #{booking.errors.full_messages.to_sentence}")
    bookings.delete(booking)
    false
  end

  # Nhận phòng cả đoàn: every room still to arrive, all or nothing. A room without a head count gets its maximum.
  def check_in_all
    arriving = rooms_booked.reject(&:checked_in_at)
    return refuse("Cả đoàn đã nhận phòng") if arriving.empty?
    transaction do
      arriving.all? do |booking|
        booking.check_in(guests: booking.guests ? nil : booking.room.max_guests) ||
          refuse("Phòng #{booking.room.name}: #{booking.errors.full_messages.to_sentence}")
      end || raise(ActiveRecord::Rollback)
    end || false
  end

  # One bill: a payment for the group becomes one Payment per billed room, filling each room's due in room order.
  def pay(amount, payment_method:, note: nil, user: nil)
    amount = Integer(VndPrice.parse(amount.to_s).to_s, exception: false)
    owing = billed.select { it.due&.positive? }
    due = owing.sum(&:due)
    return refuse("Số tiền phải lớn hơn 0") unless amount&.positive?
    return refuse("Chọn hình thức thanh toán") unless Payment::METHODS.key?(payment_method)
    return refuse("Không được lớn hơn số còn phải thu của đoàn (#{VndPrice.format(due)})") if amount > due
    transaction do
      owing.each do |booking|
        part = [ amount, booking.due ].min
        booking.payments.create!(amount: part, payment_method:, note: note.presence || "Thu theo đoàn #{code}", user:)
        break if (amount -= part).zero?
      end
    end
    true
  end

  private
    def refuse(reason)
      errors.add(:base, reason)
      false
    end
end
