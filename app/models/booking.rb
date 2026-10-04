class Booking < ApplicationRecord
  belongs_to :room
  belongs_to :calendar_feed, optional: true
  has_paper_trail on: %i[create update destroy], only: %i[start_date end_date status guests guest_name guest_phone note checked_in_at checked_out_at removed_from_feed_at],
    meta: { place_id: ->(booking) { booking.room.place_id }, room_id: :room_id }

  after_commit { Vacancy.bust }

  # Blank form fields stay nil, so saving the form unchanged logs no "— → —" change.
  normalizes :guest_name, :guest_phone, :note, with: ->(value) { value.presence }

  # Guests arriving after midnight still count as the previous day's arrivals until this hour (Huế time),
  # like a hotel's night audit: they can be checked in and stay in Hôm nay.
  LATE_ARRIVAL_UNTIL = 6

  enum :status, { hold: "hold", confirmed: "confirmed", cancelled: "cancelled" }, validate: true
  enum :source, { manual: "manual", ical: "ical" }, validate: true

  validates :start_date, presence: true
  validates :end_date, presence: true, comparison: { greater_than: :start_date }, if: :start_date
  # iCal bookings skip this: the OTA already sold those nights, so an overlap is shown as a conflict instead.
  validate :room_is_free, if: -> { manual? && (hold? || confirmed?) && room && start_date && end_date }
  validate :guests_fit_room, if: -> { guests && room }
  validate :not_cancelled_after_check_in, if: -> { cancelled? && checked_in_at }

  # Holds and confirmed stays occupy the room from start_date up to, not including, end_date —
  # or, once checked out, up to the check-out day: the remaining nights are free to sell.
  # A guest still in the room after the departure day (Quá hạn, not checked out) keeps occupying it through today;
  # on the departure day itself the room stays sellable for tonight.
  scope :blocking, -> { where(status: [ :hold, :confirmed ]) }
  scope :blocking_on, ->(date) { occupying(date, date.next_day) }
  # Bookings whose dates touch any night in from...to (to exclusive), checked out or not.
  scope :overlapping, ->(from, to) { where(start_date: ...to, end_date: from.next_day..) }
  scope :in_house, -> { where.not(checked_in_at: nil).where(checked_out_at: nil) }
  # Blocking bookings still holding a night in from...to (see occupied_until).
  scope :occupying, ->(from, to) {
    stays = blocking.where(start_date: ...to).where("checked_out_at IS NULL OR checked_out_at >= ?", from.next_day.beginning_of_day)
    dated = stays.where(end_date: from.next_day..)
    from <= Date.current ? dated.or(stays.in_house.where(end_date: ...Date.current)) : dated
  }
  scope :not_checked_in, -> { where(checked_in_at: nil) }

  # The last night this booking holds is the one before this date.
  def occupied_until
    if checked_out_at then [ end_date, checked_out_at.to_date ].min
    elsif checked_in_at && end_date < Date.current then Date.current.next_day
    else end_date
    end
  end
  def overlaps?(other) = start_date < other.occupied_until && other.start_date < occupied_until
  def early_check_in? = !checked_in_at && start_date > Date.current

  # The day whose arrivals are still expected: yesterday until LATE_ARRIVAL_UNTIL, then today.
  def self.arrival_date = (Time.current - LATE_ARRIVAL_UNTIL.hours).to_date

  def can_check_in? = check_in_refusal.nil?
  def can_check_out? = checked_in_at.present? && checked_out_at.nil?
  def can_no_show? = no_show_refusal.nil?
  def can_undo_check_in? = undo_check_in_refusal.nil?
  def can_undo_check_out? = undo_check_out_refusal.nil?

  # The guest arrived: a hold becomes confirmed. Returns false with the reason in errors[:base].
  # Records a fact, so it skips validations: a guest at the desk is checked in even if the booking conflicts
  # with an OTA booking or exceeds a lowered max_guests (the calendar shows the conflict).
  # Arriving before start_date (Nhận phòng sớm) moves start_date to today, so the extra nights are booked;
  # that changes dates, so it is validated.
  def check_in
    with_lock do
      next refuse(check_in_refusal) unless can_check_in?
      early = early_check_in?
      assign_attributes(checked_in_at: Time.current, status: :confirmed)
      if early
        self.start_date = Date.current
        save
      else
        save!(validate: false)
      end
    end
  end

  # The guest left: the room needs cleaning. The remaining nights stop blocking (see occupied_until);
  # the dates stay as booked.
  # Records a fact, so it skips validations: a guest who has left must be checked out even if the booking
  # now conflicts with an OTA booking or exceeds a lowered max_guests.
  def check_out
    with_lock do
      next refuse(checked_in_at ? "Khách đã trả phòng rồi" : "Khách chưa nhận phòng") unless can_check_out?
      self.checked_out_at = Time.current
      save!(validate: false)
      room.dirty!
      true
    end
  end

  # Hoàn tác: a wrong tap on Check-in / Check-out, put right the same day. Logged like any change.
  # An early check-in keeps its moved start_date (edit the dates if needed).
  def undo_check_in
    with_lock do
      next refuse(undo_check_in_refusal) unless can_undo_check_in?
      self.checked_in_at = nil
      save!(validate: false)
    end
  end

  # The room's housekeeping state is left alone.
  def undo_check_out
    with_lock do
      next refuse(undo_check_out_refusal) unless can_undo_check_out?
      self.checked_out_at = nil
      save!(validate: false)
    end
  end

  # The guest never came: cancel and say so in the note. Returns false with the reason in errors[:base].
  def no_show
    with_lock do
      next refuse(no_show_refusal) unless can_no_show?
      update(status: :cancelled, note: [ note.presence, "Không đến" ].compact.join(" · "))
    end
  end

  private
    def room_is_free
      return if occupied_until <= start_date
      taken = room.bookings.occupying(start_date, occupied_until).where.not(id: id).exists?
      errors.add(:base, "Phòng đã có người đặt trong khoảng ngày này") if taken
    end

    def guests_fit_room
      errors.add(:base, "Số khách phải từ 1 đến #{room.max_guests}") unless guests.in?(1..room.max_guests)
    end

    def not_cancelled_after_check_in
      errors.add(:base, "Khách đã nhận phòng, không huỷ được")
    end

    def check_in_refusal
      if cancelled? then "Đặt phòng đã huỷ"
      elsif checked_in_at then "Khách đã nhận phòng rồi"
      elsif Booking.arrival_date >= end_date then "Đặt phòng đã kết thúc"
      elsif room.bookings.in_house.where.not(id: id).exists? then "Phòng đang có khách chưa trả phòng"
      elsif early_check_in? && ical? then "Đặt phòng OTA: đổi ngày trên Airbnb / Booking.com"
      elsif early_check_in? && room.bookings.occupying(Date.current, start_date).where.not(id: id).exists?
        "Phòng chưa trống từ hôm nay"
      end
    end

    def undo_check_in_refusal
      if !checked_in_at then "Khách chưa nhận phòng"
      elsif checked_out_at then "Khách đã trả phòng, hoàn tác trả phòng trước"
      elsif checked_in_at.to_date != Date.current then "Chỉ hoàn tác được trong ngày nhận phòng"
      end
    end

    # Back in the room means holding the nights it freed again, so they must still be free.
    def undo_check_out_refusal
      if !checked_out_at then "Khách chưa trả phòng"
      elsif checked_out_at.to_date != Date.current then "Chỉ hoàn tác được trong ngày trả phòng"
      elsif room.bookings.in_house.where.not(id: id).exists? then "Phòng đang có khách khác"
      elsif (upto = end_date < Date.current ? Date.current.next_day : end_date) > Date.current &&
          room.bookings.occupying(Date.current, upto).where.not(id: id).exists?
        "Đêm còn lại đã có khách khác"
      end
    end

    # iCal bookings are excluded: the sync would confirm them again, the OTA owns them.
    def no_show_refusal
      if cancelled? then "Đặt phòng đã huỷ"
      elsif checked_in_at then "Khách đã nhận phòng rồi"
      elsif ical? then "Đặt phòng OTA: huỷ trên Airbnb / Booking.com"
      elsif Booking.arrival_date <= start_date then "Chưa qua ngày nhận phòng"
      end
    end

    def refuse(reason)
      errors.add(:base, reason)
      false
    end
end
