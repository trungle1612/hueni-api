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
  # Hoàn tác (#292): how long after Nhận / Từ chối the toast's undo is honoured.
  UNDO_MINUTES = 10

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
  # nil when every night has a room free but no one room is free for the whole stay.
  def full_from
    typed = rooms.to_a
    night = (start_date...end_date).find { |day| typed.none? { free?(it, day, day.next_day) } }
    return [ nil, nil ] unless night
    ota = Booking.ical.occupying(night, night.next_day).where(room: typed).includes(:calendar_feed).first
    [ night, ota && (ota.calendar_feed&.provider_label || "iCal") ]
  end

  SUGGEST_DAYS = 14

  # Từ chối · Hết phòng: the first stay as long as the one asked, starting within SUGGEST_DAYS after it, that hue-ni
  # would take now: free there (other pending requests hold rooms; this one won't once declined), not past the cutoff.
  def suggestion
    nights = (end_date - start_date).to_i
    typed = rooms.to_a
    from = (1..SUGGEST_DAYS).map { start_date + it }.find do |day|
      next false if day < Date.current || (day == Date.current && Time.current.hour >= place.site_cutoff_hour)
      typed.any? && place.site_free_rooms(typed, day, day + nights, except: self).any?
    end
    from && [ from, from + nights ]
  end

  # Nhận: books the room for the request's dates, held for the homestay's Giữ phòng chờ cọc when a deposit is asked.
  # The room must still be free now (an OTA or a walk-in may have taken it). Returns true, or false with errors.
  def accept(room:, deposit_percent:)
    deposit_percent = Integer(deposit_percent.to_s, exception: false)
    errors.clear
    with_lock do
      next refuse(CLOSED) unless open?
      next refuse("Cọc không hợp lệ") unless deposit_percent.in?(Place::SITE_DEPOSIT_PERCENTS)
      next refuse("Cần tài khoản chuyển khoản ở Cài đặt cơ sở để nhận cọc") if deposit_percent.positive? && !place.bank?
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

  # Hoàn tác (#292): back to pending, as if never answered. An accepted one's booking goes without a trace (its
  # versions, notifications, no Đặt phòng bị huỷ), so only while its Lịch sử is its creation alone, and never once the
  # guest was shown the bank account for a deposit (the transfer is recorded by hand, it may be on its way).
  def undo
    errors.clear
    with_lock do
      next refuse(undo_refusal) if undo_refusal
      if (booking = self.booking)
        update!(status: "pending", booking: nil, deposit_percent: nil)
        PaperTrail::Version.where(item_type: "Booking", item_id: booking.id).delete_all
        Notification.where(booking_id: booking.id).delete_all
        booking.delete
        Vacancy.bust
      else
        update!(status: "pending", decline_reason: nil, suggested_start_date: nil, suggested_end_date: nil)
      end
      true
    end
  end

  def can_undo? = undo_refusal.nil?

  def undo_refusal
    if !(accepted? || declined?) then "Yêu cầu này chưa được trả lời"
    elsif updated_at < UNDO_MINUTES.minutes.ago || !reply_by.future? then "Đã quá thời gian hoàn tác"
    elsif deposit_percent.to_i.positive? then "Khách đã thấy tài khoản để chuyển cọc, không hoàn tác được"
    elsif booking&.history&.many? then "Đặt phòng đã được sửa, thu tiền hoặc nhận phòng, không hoàn tác được"
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
