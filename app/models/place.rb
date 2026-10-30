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

  # Tài khoản chuyển khoản (#139): shown when a guest pays by Chuyển khoản. Owner-set, not from hueni.
  normalizes :bank_name, :bank_account, :bank_holder, with: ->(value) { value.squish.presence }
  validates :bank_name, :bank_holder, length: { maximum: 100 }
  validates :bank_account, length: { maximum: 30 }

  def bank? = bank_name.present? && bank_account.present?

  # Trang đặt phòng riêng (#172), owner-set: Cọc trước %, Giữ phòng chờ cọc, Hạn đặt trong ngày (same-day arrivals until this hour).
  SITE_DEPOSIT_PERCENTS = [ 0, 30, 50, 100 ].freeze
  SITE_HOLD_MINUTES = [ 15, 30, 120 ].freeze
  SITE_CUTOFF_HOURS = [ 18, 20, 22 ].freeze
  validates :site_deposit_percent, inclusion: { in: SITE_DEPOSIT_PERCENTS }
  validates :site_hold_minutes, inclusion: { in: SITE_HOLD_MINUTES }
  validates :site_cutoff_hour, inclusion: { in: SITE_CUTOFF_HOURS }
  validate -> { errors.add(:site_hidden_room_types, "không hợp lệ") unless site_hidden_room_types.is_a?(Array) && (site_hidden_room_types - Room::ROOM_TYPES.keys).empty? }
  validate -> { errors.add(:site_open, "cần ít nhất một loại phòng hiển thị") if site_room_types.empty? }, if: :site_open
  validate -> { errors.add(:site_open, "cần tài khoản chuyển khoản để nhận cọc") unless bank? }, if: -> { site_open && site_deposit_percent.positive? }

  SITE_MAX_NIGHTS = 30
  SITE_FULL = "Hết phòng loại này trong những ngày đã chọn"

  # A guest's request from the booking page: the first free switched-on room of that type (by name) for those dates,
  # held for site_hold_minutes when a deposit is asked. Returns the booking, saved or with errors. Errors never come
  # from the room checks: those name the booking in the way, another guest's.
  def book_online(room_type: nil, **fields)
    attrs = fields.slice(:start_date, :end_date, :guests, :guest_name, :guest_phone, :note).merge(online: true)
    booking = Booking.new(attrs).tap(&:validate)
    booking.errors.delete(:base)
    booking.errors.delete(:room)
    booking.errors.add(:base, "Homestay đang tạm ngưng nhận đặt phòng online") unless site_open
    booking.errors.add(:base, "Loại phòng này không nhận đặt online") unless room_type.in?(site_room_types)
    booking.errors.add(:guest_name, :blank) if booking.guest_name.blank?
    booking.errors.add(:guest_phone, :blank) if booking.guest_phone.blank?
    booking.errors.add(:guests, :blank) unless booking.guests&.positive?
    if (from = booking.start_date) && (to = booking.end_date)
      booking.errors.add(:start_date, "đã qua") if from < Date.current
      booking.errors.add(:start_date, "hôm nay chỉ nhận đặt đến #{site_cutoff_hour}:00") if from == Date.current && Time.current.hour >= site_cutoff_hour
      booking.errors.add(:end_date, "tối đa #{SITE_MAX_NIGHTS} đêm") if to - from > SITE_MAX_NIGHTS
    end
    return booking if booking.errors.any?

    fitting = rooms.where(active: true, room_type:).where(max_guests: booking.guests..).order(:name)
    return booking.tap { it.errors.add(:guests, "nhiều hơn sức chứa của loại phòng này") } if fitting.none?
    booking = fitting.map { Booking.new(room: it, **attrs) }.find(&:valid?)
    return Booking.new(attrs).tap { it.errors.add(:base, SITE_FULL) } unless booking
    booking.hold_expires_at = site_hold_minutes.minutes.from_now if site_deposit_percent.positive?
    booking.save || booking.tap { it.errors.clear; it.errors.add(:base, SITE_FULL) }
    booking
  end

  # Room types offered online: those of switched-on rooms, minus the hidden ones. Rooms without a type are not offered.
  def site_room_types = rooms.where(active: true).where.not(room_type: nil).distinct.pluck(:room_type) - site_hidden_room_types.to_a
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
end
