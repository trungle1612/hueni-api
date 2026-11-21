# Hiển thị trên hue-ni (#282), approve mode (Tôi duyệt từng yêu cầu): a guest's request from hueni.me, answered by the
# homestay (owner or staff) before reply_by, else expired. Accepting creates the Booking. While pending it holds one room
# of its type on hue-ni only (Place#site_free_rooms): the PMS calendar, vacancy and the OTA sync don't see it.
class BookingRequest < ApplicationRecord
  STATUSES = %w[pending accepted declined expired].freeze
  DECLINE_REASONS = {
    "full" => "Hết phòng loại này",
    "dates" => "Không nhận khách những ngày này",
    "rules" => "Không phù hợp quy định của cơ sở"
  }.freeze
  CLOSED = "Yêu cầu này đã được trả lời hoặc đã hết hạn"
  DAYS = 30

  belongs_to :place
  belongs_to :booking, optional: true

  enum :status, STATUSES.index_by(&:itself), validate: true
  normalizes :guest_name, :guest_phone, :note, with: ->(value) { value.strip.presence }
  validates :decline_reason, inclusion: { in: DECLINE_REASONS.keys }, if: :declined?
  validate :suggested_dates_make_sense

  scope :open, -> { pending.where(reply_by: Time.current..) }
  # Pending requests of a type with a night in from...to: each holds one room on hue-ni.
  scope :holding, ->(room_type, from, to) { open.where(room_type:, start_date: ...to, end_date: from.next_day..) }

  after_create_commit { Notification.booking_request(self) }

  def self.expire = pending.where(reply_by: ...Time.current).update_all(status: "expired", updated_at: Time.current)
  # Answered or expired requests go after DAYS days; accepted ones stay with their booking (the guest's link).
  def self.prune = where.not(status: "accepted").where(created_at: ...DAYS.days.ago).delete_all

  def code = format("YC-%04d", id)
  def open? = pending? && reply_by.future?
  # What the guest's status link says: expired as soon as the deadline passes, before expire runs.
  def site_status = pending? && !open? ? "expired" : status

  # Yêu cầu đặt phòng (#284): the switched-on rooms of its type that fit the guests (those book_online offered), and
  # the ones free on the calendar for its dates now (what Nhận can book).
  def rooms = place.rooms.where(active: true, room_type:).where(max_guests: guests..).order(:name)
  def free_rooms = rooms.select { free?(it, start_date, end_date) }
  # Tạm tính: the cheapest stay among those rooms, as hue-ni's Giá từ.
  def estimate = rooms.filter_map { Booking.new(room: it, start_date:, end_date:).room_total }.min

  # Hết phòng: the first night with no room free, and the OTA of a booking taking a room that night, if any.
  def full_from
    typed = rooms.to_a
    night = (start_date...end_date).find { |day| typed.none? { free?(it, day, day.next_day) } } || start_date
    ota = Booking.ical.occupying(night, night.next_day).where(room: typed).includes(:calendar_feed).first
    [ night, ota && (ota.calendar_feed&.provider_label || "iCal") ]
  end

  SUGGEST_DAYS = 14

  # Từ chối · Hết phòng: the first stay as long as the one asked, starting within SUGGEST_DAYS after it, with a room free.
  def suggestion
    nights = (end_date - start_date).to_i
    typed = rooms.to_a
    from = (1..SUGGEST_DAYS).map { start_date + it }.find { |day| day >= Date.current && typed.any? { free?(it, day, day + nights) } }
    from && [ from, from + nights ]
  end

  # Nhận: books the room for the request's dates, held for the homestay's Giữ phòng chờ cọc when a deposit is asked.
  # The room must still be free now (an OTA or a walk-in may have taken it). Returns true, or false with errors.
  def accept(room:, deposit_percent:)
    deposit_percent = deposit_percent.to_i
    errors.clear
    with_lock do
      next refuse(CLOSED) unless open?
      next refuse("Cọc không hợp lệ") unless deposit_percent.in?(Place::SITE_DEPOSIT_PERCENTS)
      next refuse("Phòng không thuộc cơ sở này") unless room.place_id == place_id
      next refuse("Phòng #{room.name} đang tắt") unless room.active?
      next refuse("Phòng #{room.name} không phải #{Room::ROOM_TYPES[room_type]}") unless room.room_type == room_type
      booking = room.bookings.build(start_date:, end_date:, guests:, guest_name:, guest_phone:, note:, online: true,
        hold_expires_at: (place.site_hold_minutes.minutes.from_now if deposit_percent.positive?))
      next refuse(*booking.errors.full_messages) unless booking.save
      update!(status: "accepted", booking:, deposit_percent:)
    end
  end

  # Từ chối: a reason, and for Hết phòng optionally other dates to suggest.
  def decline(reason:, suggested_start_date: nil, suggested_end_date: nil)
    errors.clear
    with_lock do
      next refuse(CLOSED) unless open?
      update(status: "declined", decline_reason: reason, suggested_start_date:, suggested_end_date:) || (restore_attributes; false)
    end
  end

  private
    def free?(room, from, to) = Booking.new(room:, start_date: from, end_date: to).date_problems.empty?

    def refuse(*messages)
      messages.each { errors.add(:base, it) }
      false
    end

    def suggested_dates_make_sense
      return if suggested_start_date.nil? && suggested_end_date.nil?
      unless suggested_start_date && suggested_end_date&.after?(suggested_start_date) && suggested_start_date >= Date.current
        errors.add(:suggested_start_date, "không hợp lệ")
      end
    end
end
