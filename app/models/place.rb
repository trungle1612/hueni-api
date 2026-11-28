class Place < ApplicationRecord
  has_many :rooms
  has_many :services, dependent: :destroy
  has_many :seasons, dependent: :destroy
  has_many :surcharges, dependent: :destroy
  has_many :cash_expenses, dependent: :destroy
  has_many :shift_closes, dependent: :destroy
  has_many :guests, dependent: :destroy
  has_many :groups, dependent: :destroy
  # The starting catalog is not someone's change: kept out of Hoạt động.
  after_create do
    PaperTrail.request(enabled: false) do
      Service::DEFAULTS.each { |name, price, unit| services.create!(name:, price:, unit:) }
      Surcharge::DEFAULTS.each { |name, price, unit| surcharges.create!(name:, price:, unit:) }
    end
  end
  has_many :place_memberships, dependent: :destroy
  has_many :invites, dependent: :delete_all
  has_many :notifications, dependent: :delete_all
  has_many :booking_requests, dependent: :delete_all
  has_many :transfers, dependent: :delete_all
  has_many :users, through: :place_memberships

  after_commit { Vacancy.bust }

  validates :slug, presence: true, uniqueness: true
  validates :name, presence: true

  # Hoa hồng % per OTA (#125), set by the owner on Kênh OTA; a blank field removes it. For Thực nhận in Báo cáo later.
  COMMISSION_PROVIDERS = %w[airbnb booking agoda].freeze
  validate do
    errors.add(:commissions, "phải là số từ 0 đến 100") unless commissions.values.all? { it.is_a?(Numeric) && it.between?(0, 100) }
  end

  # "15,5" → 15.5; anything not a number is kept so the validation names it.
  def commissions=(value)
    value = value.to_h.stringify_keys.slice(*COMMISSION_PROVIDERS).transform_values { it.to_s.strip.tr(",", ".").presence }.compact
    super(value.transform_values { Float(it, exception: false) || it })
  end

  # Đồng bộ tất cả (#125): queues every feed not synced in the last minute; returns how many.
  def sync_feeds
    feeds = CalendarFeed.where(room: rooms).reject(&:synced_recently?)
    feeds.each { SyncCalendarFeedJob.perform_later(it.id, "manual") }
    feeds.size
  end

  # Tài khoản chuyển khoản (#139): shown when a guest pays by Chuyển khoản. Owner-set, not from hueni.
  normalizes :bank_name, :bank_account, :bank_holder, with: ->(value) { value.squish.presence }
  validates :bank_name, :bank_holder, length: { maximum: 100 }
  validates :bank_account, length: { maximum: 30 }

  def bank? = bank_name.present? && bank_account.present?

  # The last owner deleted their account (#192): bookings with their money, guest notes, groups and their history go,
  # with every membership here. The homestay (hueni's copy), its rooms, feeds and settings stay for a new owner.
  def clear_for_deleted_owner!
    bookings = Booking.where(room_id: rooms.select(:id))
    transaction do
      RefundRequest.where(booking: bookings).delete_all
      Payment.where(booking: bookings).delete_all
      BookingCharge.where(booking: bookings).delete_all
      booking_requests.delete_all
      bookings.delete_all
      groups.delete_all
      guests.delete_all
      PaperTrail::Version.where(place_id: id, item_type: %w[Booking Payment BookingCharge RefundRequest Group Guest]).delete_all
      place_memberships.delete_all
      invites.delete_all
      notifications.delete_all
    end
    Vacancy.bust
  end

  # Trang đặt phòng riêng (#172), owner-set: Cọc trước %, Giữ phòng chờ cọc, Hạn đặt trong ngày (same-day arrivals until this hour).
  SITE_DEPOSIT_PERCENTS = [ 0, 30, 50, 100 ].freeze
  SITE_HOLD_MINUTES = [ 15, 30, 120 ].freeze
  SITE_CUTOFF_HOURS = [ 18, 20, 22 ].freeze
  validates :site_deposit_percent, inclusion: { in: SITE_DEPOSIT_PERCENTS }
  validates :site_hold_minutes, inclusion: { in: SITE_HOLD_MINUTES }
  validates :site_cutoff_hour, inclusion: { in: SITE_CUTOFF_HOURS }
  validate -> { errors.add(:site_hidden_room_types, "không hợp lệ") unless site_hidden_room_types.is_a?(Array) && (site_hidden_room_types - Room::ROOM_TYPES.keys).empty? }
  validate -> { errors.add(:site_hidden_room_ids, "không hợp lệ") unless site_hidden_room_ids.is_a?(Array) && site_hidden_room_ids.all?(Integer) }
  validate -> { errors.add(:site_open, "cần ít nhất một phòng hiển thị") unless site_rooms.exists? }, if: :site_open
  validate -> { errors.add(:site_open, SITE_CHECKLIST["bank"]) if site_deposit_percent.to_i.positive? && !bank? }, if: :site_open, unless: :will_save_change_to_site_open?

  # Hiển thị trên hue-ni (#282): Tôi duyệt từng yêu cầu (approve: BookingRequest, answered within site_reply_minutes) or
  # Tự nhận khi còn phòng (auto: book_online books at once); Báo khách số điện thoại sau khi nhận.
  SITE_MODES = %w[approve auto].freeze
  SITE_REPLY_MINUTES = [ 15, 30, 120 ].freeze
  validates :site_mode, inclusion: { in: SITE_MODES }
  validates :site_reply_minutes, inclusion: { in: SITE_REPLY_MINUTES }
  # Giờ nhận, trả phòng and Quy định, shown to guests.
  normalizes :check_in_time, :check_out_time, :house_rules, with: ->(value) { value.strip.presence }
  validates :check_in_time, :check_out_time, format: { with: /\A([01]\d|2[0-3]):[0-5]\d\z/, message: "phải theo dạng 14:00" }, allow_nil: true
  validates :house_rules, length: { maximum: 2000 }

  # Thông tin cần có before the page can be turned on, by checklist item: the error when it's missing.
  SITE_CHECKLIST = {
    "photos" => "cần ảnh cho mỗi phòng hiển thị",
    "map" => "cần vị trí trên bản đồ",
    "rules" => "cần giờ nhận, trả phòng",
    "bank" => "cần tài khoản chuyển khoản để nhận cọc"
  }.freeze
  validate if: -> { site_open && will_save_change_to_site_open? } do
    site_missing.each { errors.add(:site_open, SITE_CHECKLIST[it]) unless errors.added?(:site_open, SITE_CHECKLIST[it]) }
  end

  # The items that count: the bank only when a Cọc is asked.
  def site_required = site_deposit_percent.to_i.positive? ? SITE_CHECKLIST.keys : SITE_CHECKLIST.keys - %w[bank]

  # The checklist items not done yet. Ảnh: every shown room has a photo. Bản đồ: hueni's pin.
  def site_missing(required = site_required)
    { "photos" => !site_rooms.exists? || site_rooms.where.missing(:photos).exists?, "map" => lat.nil? || lng.nil?,
      "rules" => check_in_time.nil? || check_out_time.nil?, "bank" => !bank? }.filter_map { |item, missing| item if missing && required.include?(item) }
  end

  # Đưa đón sân bay (#306): partner homestays only; the guest pays the driver in cash, so it is never billed here.
  TRANSFER_AIRPORT = "Sân bay Phú Bài"
  TRANSFER_REFUSED = "Cơ sở này chưa có dịch vụ đưa đón sân bay"
  normalizes :driver_phone, with: ->(value) { value.strip.presence }
  validates :transfer_price, numericality: { greater_than_or_equal_to: 0, only_integer: true }

  SITE_MAX_NIGHTS = 30
  SITE_FULL = "Hết phòng trong những ngày đã chọn"
  SITE_ROOM_FULL = "Phòng này đã có khách trong những ngày đã chọn"

  # A guest's request from the booking page. Auto mode: the first free shown room (by name) that fits, for those dates,
  # held for site_hold_minutes when a deposit is asked. Approve mode: a BookingRequest, if a room is free. room_id (#290,
  # #302): that room instead. room_type (older hue-ni): only rooms of that type. Returns the booking or request,
  # saved or with errors. Errors never come from the room checks: those name the booking in the way, another guest's.
  def book_online(room_type: nil, room_id: nil, transfer: nil, **fields)
    pool = site_rooms.order(:name).to_a
    room = pool.find { it.id.to_s == room_id.to_s } if room_id.present?
    typed = room_type.present? ? pool.select { it.room_type == room_type } : pool
    attrs = fields.slice(:start_date, :end_date, :guests, :guest_name, :guest_phone, :note).merge(online: true)
    booking = Booking.new(attrs).tap(&:validate)
    booking.errors.delete(:base)
    booking.errors.delete(:room)
    booking.errors.add(:base, "Homestay đang tạm ngưng nhận đặt phòng online") unless site_open
    if room_id.present? ? room.nil? : typed.empty?
      booking.errors.add(:base, room_id.present? ? "Phòng này không nhận đặt online" : room_type.present? ? "Loại phòng này không nhận đặt online" : "Homestay chưa có phòng nhận đặt online")
    end
    legs = transfer_legs(transfer, booking, booking.errors)
    booking.errors.add(:guest_name, :blank) if booking.guest_name.blank?
    booking.errors.add(:guest_phone, :blank) if booking.guest_phone.blank?
    booking.errors.add(:guests, :blank) unless booking.guests&.positive?
    if (from = booking.start_date) && (to = booking.end_date)
      booking.errors.add(:start_date, "đã qua") if from < Date.current
      booking.errors.add(:start_date, "hôm nay chỉ nhận đặt đến #{site_cutoff_hour}:00") if from == Date.current && Time.current.hour >= site_cutoff_hour
      booking.errors.add(:end_date, "tối đa #{SITE_MAX_NIGHTS} đêm") if to - from > SITE_MAX_NIGHTS
    end
    return booking if booking.errors.any?

    if (room ? [ room ] : typed).none? { it.max_guests >= booking.guests }
      return booking.tap { it.errors.add(:guests, "nhiều hơn sức chứa của #{room ? "phòng này" : room_type.present? ? "loại phòng này" : "mọi phòng"}") }
    end
    free = site_free_rooms(pool, from, to, guests: booking.guests) & typed
    booking = (room ? (room if free.include?(room)) : free.first)&.then { Booking.new(room: it, **attrs) }
    full = room ? SITE_ROOM_FULL : SITE_FULL
    return Booking.new(attrs).tap { it.errors.add(:base, full) } unless booking&.valid?
    if site_mode == "approve"
      return transaction do
        booking_requests.create!(room_type: room_type.presence, room:, reply_by: site_reply_minutes.minutes.from_now, **attrs.except(:online)).tap { it.transfers.create!(legs) }
      end
    end
    booking.hold_expires_at = site_hold_minutes.minutes.from_now if site_deposit_percent.positive?
    transaction do
      booking.save ? booking.transfers.create!(legs) : booking.tap { it.errors.clear; it.errors.add(:base, full) }
    end
    booking
  end

  # transfer: { arrival: { time:, flight: }, departure: true } → the legs to create (price snapshotted, dates = the
  # stay's), or errors on `errors` (refused outright when this isn't a partner, never silently dropped).
  def transfer_legs(transfer, stay, errors)
    transfer = (transfer.to_h.deep_symbolize_keys if transfer.respond_to?(:to_h))
    arrival, departure = transfer&.values_at(:arrival, :departure)
    departure = ActiveModel::Type::Boolean.new.cast(departure)
    return [] if arrival.blank? && !departure
    return errors.add(:base, TRANSFER_REFUSED).then { [] } unless transfer_partner
    legs = []
    legs << { kind: "arrival", date: stay.start_date, pickup_time: arrival[:time].presence, flight: arrival[:flight], price: transfer_price, place: self } if arrival.present?
    legs << { kind: "departure", date: stay.end_date, price: transfer_price, place: self } if departure
    legs.each do |leg|
      probe = Transfer.new(leg).tap(&:validate)
      probe.errors.each { errors.add(:base, "#{Transfer.human_attribute_name(it.attribute).downcase} #{it.message}") }
    end
    legs
  end

  # Rooms hue-ni can sell for from...to, each on its own: free on the calendar, and taking it leaves every
  # pending request as well served on each of its nights (#290): a request needs the room its guest picked while that
  # room is free for its stay, else any room that fits its guests (an OTA took the picked room, or none was picked). except: a request not to count. guests: only rooms that fit.
  def site_free_rooms(typed, from, to, except: nil, guests: 1)
    pool, holds = site_stock(typed, from, to, except)
    pool.select { it.max_guests >= guests.to_i && site_keeps_holds?(holds, pool, [ it ], from, to) }
  end

  # How many more stays hue-ni can take for from...to: rooms taken one by one while the pending requests keep theirs.
  def site_rooms_left(typed, from, to)
    pool, holds = site_stock(typed, from, to, nil)
    pool.each_with_object([]) { |room, taken| taken << room if site_keeps_holds?(holds, pool, taken + [ room ], from, to) }.size
  end

  # Rooms offered online (#302): the switched-on rooms minus the hidden ones, whatever their type.
  def site_rooms = rooms.where(active: true).where.not(id: site_hidden_room_ids.to_a)
  # Their types, for the frozen Mini App and older hue-ni builds. Nothing is decided by it.
  def site_room_types = site_rooms.where.not(room_type: nil).distinct.pluck(:room_type)
  # Chính sách huỷ (#163): shown to guests (booking page, confirmation); refunds stay the owner's call.
  CANCEL_POLICIES = {
    "flex" => [ "Linh hoạt", "Huỷ miễn phí trước 24 giờ. Sau đó mất cọc." ],
    "mid" => [ "Vừa phải", "Huỷ miễn phí trước 3 ngày. Sau đó mất cọc. Không đến: tính 1 đêm." ],
    "strict" => [ "Không hoàn", "Không hoàn cọc dù huỷ lúc nào." ]
  }.freeze
  validates :cancel_policy, inclusion: { in: CANCEL_POLICIES.keys }

  # Mùa (#163): the highest season % covering the night, 0 outside every season.
  def season_percent_on(date) = seasons.covering(date).maximum(:percent).to_i

  # Booking codes (#124): one UPDATE, so two bookings saved at once never share a number.
  def next_booking_number!
    Place.where(id:).update_all("last_booking_number = last_booking_number + 1")
    Place.where(id:).pick(:last_booking_number)
  end

  # Group codes DOAN-0001 (#164), the same way.
  def next_group_number!
    Place.where(id:).update_all("last_group_number = last_group_number + 1")
    Place.where(id:).pick(:last_group_number)
  end

  # Upserts places from hueni's homestay.json "places" array, keyed by slug. Never deletes.
  def self.import(hueni_places)
    counts = { created: 0, updated: 0, unchanged: 0 }
    transaction do
      hueni_places.each do |hp|
        place = find_or_initialize_by(slug: hp.fetch("id"))
        place.assign_attributes(
          name: hp.fetch("name"),
          address: hp["address"],
          phone: hp["phone"],
          rating: hp["rating"],
          lat: hp.dig("coordinates", "lat"),
          lng: hp.dig("coordinates", "lng"),
          website: hp["website"],
          cover_image_url: hp["coverImage"],
          google_place_id: hp["place_id"]
        )
        counts[place.new_record? ? :created : place.changed? ? :updated : :unchanged] += 1
        place.save!
      end
    end
    counts
  end

  private
    # The calendar-free rooms, and each pending request's need: [first night, departure, rooms it can use]. A picked
    # room free for the request's stay but busy in from...to holds nothing here.
    def site_stock(typed, from, to, except)
      return [ [], [] ] if typed.empty?
      free = ->(room, first, last) { Booking.new(room:, start_date: first, end_date: last).date_problems.empty? }
      pool = typed.select { free.(it, from, to) }
      holds = booking_requests.holding(from, to).where.not(id: except).includes(:room).filter_map do |request|
        picked = request.room if request.room.in?(typed) && free.(request.room, request.start_date, request.end_date)
        next if picked && !picked.in?(pool)
        [ request.start_date, request.end_date, picked ? [ picked ] : typed.select { it.max_guests >= request.guests && (request.room_type.nil? || it.room_type == request.room_type) } ]
      end
      [ pool, holds ]
    end

    # Taking these rooms serves as many requests on every night as the whole pool does.
    def site_keeps_holds?(holds, pool, taken, from, to)
      rest = pool - taken
      (from...to).map { |night| holds.select { |first, last, _| night >= first && night < last } }.uniq
        .all? { |active| site_served(active, rest) == site_served(active, pool) }
    end

    # Most requests given a room at once (augmenting paths; a handful of requests and rooms per type).
    def site_served(holds, rooms)
      match = {}
      holds.count { |hold| site_augment(hold, rooms, match, Set.new) }
    end

    def site_augment(hold, rooms, match, seen)
      (hold.last & rooms).any? do |room|
        seen.add?(room) && (match[room].nil? || site_augment(match[room], rooms, match, seen)) && (match[room] = hold)
      end
    end
end
