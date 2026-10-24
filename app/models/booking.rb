class Booking < ApplicationRecord
  include VndPrice

  belongs_to :room
  belongs_to :calendar_feed, optional: true
  # Saved on their own (Payment checks the balance), never along with the booking.
  has_many :payments, dependent: :destroy, autosave: false, validate: false
  has_paper_trail on: %i[create update destroy], only: %i[room_id start_date end_date status guests guest_name guest_phone note price weekend_price cancel_reason checked_in_at checked_out_at removed_from_feed_at declared_at],
    meta: { place_id: ->(booking) { booking.room.place_id }, room_id: :room_id }

  after_commit { Vacancy.bust }

  # The quote: the room's prices when the booking was made. A later room price change (or a room move) keeps it.
  vnd_price :price, :weekend_price
  # Đã cọc on the new-booking form: saved as the first payment (#139).
  attribute :deposit, :integer
  attribute :deposit_method, :string, default: "cash"
  vnd_price :deposit
  validates :deposit_method, inclusion: { in: Payment::METHODS.keys }, if: :deposit
  validate -> { errors.add(:deposit, "không được lớn hơn tiền phòng (#{VndPrice.format(room_total)})") if deposit && room_total && deposit > room_total }, on: :create
  after_create { payments.create!(amount: deposit, payment_method: deposit_method, note: "Cọc", user: Current.user) if deposit&.positive? }
  before_create { self.price, self.weekend_price = room.price, room.weekend_price if price.nil? && room }
  # Booking code DP-0142 (#124): next number of the homestay, manual and iCal alike. Kept on a room move (same homestay).
  before_create { self.number = room.place.next_booking_number! if room }

  # Blank form fields stay nil, so saving the form unchanged logs no "— → —" change.
  normalizes :guest_name, :guest_phone, :note, with: ->(value) { value.strip.presence }

  # Guests arriving after midnight still count as the previous day's arrivals until this hour (Huế time),
  # like a hotel's night audit: they can be checked in and stay in Hôm nay.
  LATE_ARRIVAL_UNTIL = 6

  # No Giữ chỗ (#127): a booking is confirmed or cancelled; payments say whether money came in.
  enum :status, { confirmed: "confirmed", cancelled: "cancelled" }, validate: true
  enum :source, { manual: "manual", ical: "ical" }, validate: true
  # Status changes go through these events, so side effects (notifications, tracking) hang off them.
  # The iCal sync writes status directly: its bookings are created confirmed and never change status.
  include AASM
  aasm column: :status, enum: true, whiny_transitions: false, whiny_persistence: false do
    state :confirmed, initial: true
    state :cancelled

    event(:cancel) { transitions from: :confirmed, to: :cancelled }
    event(:reopen) { transitions from: :cancelled, to: :confirmed }
  end

  # Huỷ đặt phòng asks why (#123): a preset, or the text typed under Khác (cancel_reason "other").
  CANCEL_REASONS = [ "Khách huỷ", "Không đến", "Đặt nhầm" ].freeze
  attr_accessor :cancel_reason_other
  normalizes :cancel_reason, with: ->(value) { value.strip.presence }
  before_validation { self.cancel_reason = cancel_reason_other if cancel_reason == "other" }
  before_save { self.cancel_reason = nil if confirmed? }
  validates :cancel_reason, presence: true, length: { maximum: 200 }, if: -> { persisted? && manual? && cancelled? && will_save_change_to_status? }

  validates :start_date, presence: true
  validates :end_date, presence: true, comparison: { greater_than: :start_date, message: "phải sau ngày nhận phòng (ít nhất 1 đêm)" }, if: :start_date
  # iCal bookings skip this: the OTA already sold those nights, so an overlap is shown as a conflict instead.
  validate :room_is_free, if: -> { manual? && confirmed? && room && start_date && end_date }
  # Only when the stay is new or moves: an existing booking caught by a later Bảo trì shows as a calendar conflict instead.
  validate :room_not_in_maintenance, if: -> { manual? && confirmed? && room && start_date && end_date &&
    (new_record? || will_save_change_to_start_date? || will_save_change_to_end_date? || will_save_change_to_room_id? || will_save_change_to_status?) }
  validate :guests_fit_room, if: -> { guests && room }
  validates :guest_name, length: { maximum: 100 }
  # Kept as typed (foreign guests: "+82 10 1234 5678"), but it must be dialable for the Gọi button.
  validate -> { errors.add(:guest_phone, "không hợp lệ: cần 8–15 chữ số") unless guest_phone.match?(/\A\+?[\d\s.\-()]+\z/) && guest_phone.count("0-9").between?(8, 15) },
    if: :guest_phone
  validate :not_cancelled_after_check_in, if: -> { cancelled? && checked_in_at }

  # Confirmed stays occupy the room from start_date up to, not including, end_date —
  # or, once checked out, up to the check-out day: the remaining nights are free to sell.
  # A guest still in the room after the departure day (Quá hạn, not checked out) keeps occupying it through today;
  # on the departure day itself the room stays sellable for tonight.
  scope :blocking, -> { confirmed }
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
  # How the calendar, Hôm nay and messages name a booking.
  def guest_phone_dial = guest_phone&.gsub(/[^\d+]/, "")
  def code = number && format("DP-%04d", number)
  def label = guest_name.presence || note.presence || (ical? ? calendar_feed&.provider_label || "iCal" : "Khách")
  def overlaps?(other) = start_date < other.occupied_until && other.start_date < occupied_until
  # One night's price: Friday and Saturday nights use the weekend price. Unquoted bookings (the room had no price
  # then) use the room's current prices; nil = unpriced.
  def price_on(date)
    weekday, weekend = price ? [ price, weekend_price ] : [ room.price, room.weekend_price ]
    (weekend if date.friday? || date.saturday?) || weekday
  end
  # Thanh toán (#139): every booked night at its price; nil while a night has no price.
  def room_total
    return unless room && start_date && end_date
    prices = (start_date...end_date).map { price_on(it) }
    prices.sum unless prices.include?(nil)
  end

  # Saved payments minus refunds. OTA bookings are paid on the OTA: nothing is due here.
  def paid = payments.reject(&:new_record?).sum(&:signed_amount)
  def due = (room_total - paid if manual? && room_total)

  # Chưa cọc: a direct booking not yet checked in with nothing paid (the calendar's amber bar, like the Zalo app).
  def awaiting_deposit? = manual? && !checked_in_at && !paid.positive?
  # Holds a night the room is under Bảo trì (today through maintenance_until).
  def in_maintenance? = room.maintenance? && start_date <= room.maintenance_until && occupied_until > Date.current
  def early_check_in? = !checked_in_at && start_date > Date.current

  # What the booking form's availability line shows: the date and overlap messages this stay would get in its
  # room, from the same validations as saving. [] = free.
  def date_problems
    probe = Booking.new(room:, start_date:, end_date:, id:)
    probe.validate
    %i[start_date end_date].flat_map { probe.errors.full_messages_for(it) } + probe.errors[:base]
  end

  # The day whose arrivals are still expected: yesterday until LATE_ARRIVAL_UNTIL, then today.
  def self.arrival_date = (Time.current - LATE_ARRIVAL_UNTIL.hours).to_date

  def can_check_in? = check_in_refusal.nil?
  def can_check_out? = checked_in_at.present? && checked_out_at.nil?
  def can_no_show? = no_show_refusal.nil?
  def can_move_to?(other_room) = move_refusal(other_room).nil?
  def can_undo_check_in? = undo_check_in_refusal.nil?
  def can_undo_check_out? = undo_check_out_refusal.nil?

  # Saves attributes, moving to attributes[:status] through its event. Returns false with the reason in errors[:base].
  def update_with_status(attributes)
    attributes = attributes.to_h.symbolize_keys
    to = attributes.delete(:status).presence&.to_sym
    assign_attributes(attributes)
    return save if to.nil? || to == aasm.current_state
    event = aasm.events(permitted: true).find { it.transitions_to_state?(to) }
    event ? aasm.fire!(event.name, to) : refuse("Không chuyển được sang trạng thái này")
  end

  # The guest arrived. Returns false with the reason in errors[:base].
  # Records a fact, so it skips validations: a guest at the desk is checked in even if the booking conflicts
  # with an OTA booking or exceeds a lowered max_guests (the calendar shows the conflict).
  # Arriving before start_date (Nhận phòng sớm) moves start_date to today, so the extra nights are booked;
  # that changes dates, so it is validated.
  # guests: the head count taken at the desk (the admin asks for it when the booking has none).
  def check_in(guests: nil)
    with_lock do
      next refuse(check_in_refusal) unless can_check_in?
      if guests
        next refuse("Số khách phải từ 1 đến #{room.max_guests}") unless guests.in?(1..room.max_guests)
        self.guests = guests
      end
      early = early_check_in?
      self.checked_in_at = Time.current
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

  # Hoàn tác: a wrong tap on Nhận phòng / Trả phòng, put right the same day. Logged like any change.
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

  # Đổi phòng: an in-house guest moves to another free room of the same homestay. The whole booking moves
  # (no split stays); the old room needs cleaning.
  def move_to(other_room)
    with_lock do
      next refuse(move_refusal(other_room)) unless can_move_to?(other_room)
      old_room = room
      self.room = other_room
      save!(validate: false)
      old_room.dirty!
      true
    end
  end

  # Khai báo lưu trú done for this stay: only a reminder, it blocks nothing.
  def declare
    with_lock do
      next refuse("Khách chưa nhận phòng") unless checked_in_at
      next refuse("Đã khai báo lưu trú rồi") if declared_at
      self.declared_at = Time.current
      save!(validate: false)
    end
  end

  def needs_declaration? = can_check_out? && !declared_at
  # Still in the room after the departure day (Quá hạn): occupies it through today, see occupied_until.
  def overdue? = can_check_out? && end_date < Date.current
  # Due out today and not checked out yet.
  def departing_today? = can_check_out? && end_date == Date.current

  # The guest never came: cancel with reason Không đến. Returns false with the reason in errors[:base].
  def no_show
    with_lock do
      next refuse(no_show_refusal) unless can_no_show?
      self.cancel_reason = "Không đến"
      cancel!
    end
  end

  private
    # Names the first booking in the way and the nights both want, so the owner knows what to fix.
    def room_is_free
      return if occupied_until <= start_date
      taken = room.bookings.occupying(start_date, occupied_until).where.not(id: id).includes(:calendar_feed).order(:start_date, :id).to_a
      return if taken.empty?
      other = taken.first
      first, last = [ start_date, other.start_date ].max, [ occupied_until, other.occupied_until ].min.prev_day
      nights = [ first, last ].uniq.map { it.strftime("%d/%m") }.join("–")
      more = " và #{taken.size - 1} đặt phòng khác" if taken.size > 1
      errors.add(:base, "Trùng lịch đêm #{nights} với #{other.label} (#{other.start_date.strftime("%d/%m")}–#{other.end_date.strftime("%d/%m")})#{more}. " \
        "Đổi ngày hoặc huỷ đặt phòng bị trùng.")
    end

    def room_not_in_maintenance
      return unless in_maintenance?
      errors.add(:base, "Phòng bảo trì đến #{room.maintenance_until.strftime("%d/%m")} (#{room.maintenance_reason}). " \
        "Chọn ngày từ #{room.maintenance_until.next_day.strftime("%d/%m")} hoặc phòng khác.")
    end

    def guests_fit_room
      errors.add(:guests, "phải từ 1 đến #{room.max_guests}") unless guests.in?(1..room.max_guests)
    end

    def not_cancelled_after_check_in
      errors.add(:base, "Khách đã nhận phòng, không huỷ được")
    end

    def check_in_refusal
      if cancelled? then "Đặt phòng đã huỷ"
      elsif checked_in_at then "Khách đã nhận phòng rồi"
      elsif Booking.arrival_date >= end_date then "Đặt phòng đã kết thúc"
      elsif room.bookings.in_house.where.not(id: id).exists? then "Phòng đang có khách chưa trả phòng"
      elsif room.maintenance_on?(Date.current) then "Phòng đang bảo trì"
      elsif early_check_in? && ical? then "Đặt phòng OTA: đổi ngày trên Airbnb / Booking.com"
      elsif early_check_in? && room.bookings.occupying(Date.current, start_date).where.not(id: id).exists?
        "Phòng chưa trống từ hôm nay"
      end
    end

    def move_refusal(other_room)
      if ical? then "Đặt phòng OTA: đổi phòng trên Airbnb / Booking.com"
      elsif !can_check_out? then "Chỉ đổi phòng khi khách đang ở"
      elsif other_room == room then "Khách đang ở phòng này"
      elsif other_room.place_id != room.place_id then "Chỉ đổi được sang phòng cùng homestay"
      elsif !other_room.active? then "Phòng #{other_room.name} đang tắt"
      elsif other_room.maintenance_on?(Date.current) then "Phòng #{other_room.name} đang bảo trì"
      elsif guests && guests > other_room.max_guests then "Phòng #{other_room.name} tối đa #{other_room.max_guests} khách"
      elsif other_room.bookings.in_house.exists? || other_room.bookings.occupying(Date.current, occupied_until).exists?
        "Phòng #{other_room.name} không trống tới ngày trả phòng"
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
