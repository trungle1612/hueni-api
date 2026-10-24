class Room < ApplicationRecord
  include VndPrice

  belongs_to :place
  has_many :bookings
  has_many :calendar_feeds
  # Becoming dirty is part of check-out, so only "dọn xong" (→ clean) and Bảo trì are logged.
  has_paper_trail on: %i[create update destroy], only: [ :name, :max_guests, :price, :weekend_price, :active, :maintenance_reason, :maintenance_until,
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
  with_options if: :maintenance? do
    validates :maintenance_reason, presence: true, length: { maximum: 200 }
    validates :maintenance_until, presence: true
    validates :maintenance_until, comparison: { greater_than_or_equal_to: -> { Date.current }, message: "không được trước hôm nay" },
      if: -> { maintenance_until && will_save_change_to_maintenance_until? }
    validate -> { errors.add(:base, "Phòng đang có khách. Đổi tình trạng được sau khi trả phòng.") if bookings.in_house.exists? },
      if: :will_save_change_to_housekeeping?
  end

  # Upcoming stays that keep the price they were quoted when this room's price changes.
  def quoted_bookings = bookings.blocking.where(end_date: Date.current.next_day..).where(checked_out_at: nil)

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

  def weekend_price_below_price? = weekend_price && price && weekend_price < price

  private
    def photo_urls_are_http_urls
      valid = photo_urls.is_a?(Array) && photo_urls.all? { it.is_a?(String) && it.match?(%r{\Ahttps?://\S+\z}) }
      errors.add(:photo_urls, :invalid) unless valid
    end
end
