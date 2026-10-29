class Room < ApplicationRecord
  include VndPrice

  belongs_to :place
  has_many :bookings
  has_many :calendar_feeds, dependent: :destroy
  has_many :cleaning_tasks, dependent: :destroy
  # Becoming dirty is part of check-out, so only "dọn xong" (→ clean) and Bảo trì are logged.
  has_paper_trail on: %i[create update destroy], only: [ :name, :max_guests, :price, :weekend_price, :active, :maintenance_reason, :maintenance_until, :floor, :room_type, :amenities, :note, :damage_note,
    { housekeeping: ->(room) { !room.dirty? } } ],
    meta: { place_id: :place_id, room_id: :id }

  after_commit { Vacancy.bust }

  # maintenance = Bảo trì (#121): blocked from today through maintenance_until, see maintenance_on?.
  enum :housekeeping, { clean: "clean", dirty: "dirty", maintenance: "maintenance" }, validate: true
  normalizes :maintenance_reason, with: ->(value) { value.strip.presence }
  before_save { self.maintenance_reason = self.maintenance_until = nil unless maintenance? }

  validates :name, presence: true, uniqueness: { scope: :place_id }
  validates :max_guests, numericality: { only_integer: true, greater_than: 0 }
  # weekend_price: Friday and Saturday nights; blank = the weekday price.
  vnd_price :price, :weekend_price
  validate :photo_urls_are_http_urls

  # Loại phòng (#138): a fixed list; keys in the DB (check constraint), labels on screen.
  ROOM_TYPES = { "single" => "Phòng đơn", "double" => "Phòng đôi", "family" => "Phòng gia đình", "dorm" => "Dorm", "studio" => "Studio", "villa" => "Villa" }.freeze
  enum :room_type, ROOM_TYPES.keys.index_with(&:itself), prefix: true, validate: { allow_nil: true }
  # Tiện nghi (#138): keys, labels for the form and the booking page.
  AMENITIES = { "ac" => "Máy lạnh", "window" => "Cửa sổ", "balcony" => "Ban công", "bathtub" => "Bồn tắm", "kitchen" => "Bếp nhỏ", "desk" => "Bàn làm việc" }.freeze
  normalizes :note, with: ->(value) { value.strip.presence }
  validates :floor, numericality: { only_integer: true, in: 0..200 }, allow_nil: true
  validates :note, length: { maximum: 1000 }
  # Báo hỏng hoặc thiếu đồ (#166): shown until cleared; blocks nothing, the owner sets Bảo trì for that.
  normalizes :damage_note, with: ->(value) { value.squish.presence }
  validates :damage_note, length: { maximum: 200 }
  # Xoá phòng (#122): only a room that never had a booking (one added by mistake), so history and Báo cáo stay whole.
  before_destroy prepend: true do
    next unless bookings.exists?
    errors.add(:base, "Phòng đã có đặt phòng nên không xoá được.")
    throw :abort
  end
  with_options if: :maintenance? do
    validates :maintenance_reason, presence: true, length: { maximum: 200 }
    validates :maintenance_until, presence: true
    validates :maintenance_until, comparison: { greater_than_or_equal_to: -> { Date.current }, message: "không được trước hôm nay" },
      if: -> { maintenance_until && will_save_change_to_maintenance_until? }
    validate -> { errors.add(:base, "Phòng đang có khách. Đổi tình trạng được sau khi trả phòng.") if bookings.in_house.exists? },
      if: :will_save_change_to_housekeeping?
  end

  # Stays not over yet: they keep their quoted price when this room's price changes, and block Xoá phòng.
  def upcoming_bookings = bookings.blocking.where(end_date: Date.current.next_day..).where(checked_out_at: nil)

  def maintenance_on?(date) = maintenance? && maintenance_until >= date

  # Trạng thái on the room form: Nhận khách / Bảo trì / Tạm ngưng.
  def state = maintenance? ? "maintenance" : (active? ? "active" : "paused")

  def state=(value)
    self.active = value != "paused"
    if value == "maintenance" then self.housekeeping = "maintenance"
    elsif maintenance? then self.housekeeping = "clean"
    end
  end

  # Daily: Bảo trì past its last day ends; the room needs cleaning before the next guest.
  def self.end_maintenance = maintenance.where(maintenance_until: ...Date.current).find_each { it.update!(housekeeping: "dirty") }

  # Checkbox lists send a blank first value; keep AMENITIES order.
  def amenities=(value)
    super(AMENITIES.keys & Array(value))
  end

  def amenity_labels = AMENITIES.values_at(*amenities)

  def room_type_label = ROOM_TYPES[room_type]

  def weekend_price_below_price? = weekend_price && price && weekend_price < price

  # What the owner should know after saving (#120, #122): upcoming bookings keep their quoted price; a weekend price below
  # the weekday one; stays with more guests than a lowered Số khách tối đa (the room still saves).
  def change_notes
    notes = []
    if saved_change_to_price? || saved_change_to_weekend_price?
      kept = upcoming_bookings.count
      notes << "#{kept} đặt phòng sắp tới giữ giá cũ." if kept.positive?
      notes << "Giá thứ 6, thứ 7 đang thấp hơn ngày thường, kiểm tra lại nếu không cố ý." if weekend_price_below_price?
    end
    if saved_change_to_max_guests?
      upcoming_bookings.where(guests: (max_guests + 1)..).order(:start_date).each do
        notes << "Đặt phòng #{it.start_date.strftime("%d/%m")}–#{it.end_date.strftime("%d/%m")} có #{it.guests} khách, nhiều hơn tối đa #{max_guests}."
      end
    end
    notes
  end

  private
    def photo_urls_are_http_urls
      valid = photo_urls.is_a?(Array) && photo_urls.all? { it.is_a?(String) && it.match?(%r{\Ahttps?://\S+\z}) }
      errors.add(:photo_urls, :invalid) unless valid
    end
end
