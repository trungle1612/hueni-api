class Room < ApplicationRecord
  include VndPrice

  belongs_to :place
  has_many :bookings
  has_many :calendar_feeds
  # Becoming dirty is part of check-out, so only "dọn xong" (→ clean) is logged.
  has_paper_trail on: %i[create update destroy], only: [ :name, :max_guests, :price, :weekend_price, :active, { housekeeping: ->(room) { room.clean? } } ],
    meta: { place_id: :place_id, room_id: :id }

  after_commit { Vacancy.bust }

  enum :housekeeping, { clean: "clean", dirty: "dirty" }, validate: true

  validates :name, presence: true, uniqueness: { scope: :place_id }
  validates :max_guests, numericality: { only_integer: true, greater_than: 0 }
  # weekend_price: Friday and Saturday nights; blank = the weekday price.
  vnd_price :price, :weekend_price
  validate :photo_urls_are_http_urls

  # Upcoming stays that keep the price they were quoted when this room's price changes.
  def quoted_bookings = bookings.blocking.where(end_date: Date.current.next_day..).where(checked_out_at: nil)

  def weekend_price_below_price? = weekend_price && price && weekend_price < price

  private
    def photo_urls_are_http_urls
      valid = photo_urls.is_a?(Array) && photo_urls.all? { it.is_a?(String) && it.match?(%r{\Ahttps?://\S+\z}) }
      errors.add(:photo_urls, :invalid) unless valid
    end
end
