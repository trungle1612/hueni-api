class Room < ApplicationRecord
  belongs_to :place
  has_many :bookings
  has_many :calendar_feeds
  # Becoming dirty is part of check-out, so only "dọn xong" (→ clean) is logged.
  has_paper_trail on: %i[create update destroy], only: [ :name, :max_guests, :price, :active, { housekeeping: ->(room) { room.clean? } } ],
    meta: { place_id: :place_id, room_id: :id }

  after_commit { Vacancy.bust }

  enum :housekeeping, { clean: "clean", dirty: "dirty" }, validate: true

  validates :name, presence: true, uniqueness: { scope: :place_id }
  validates :max_guests, numericality: { only_integer: true, greater_than: 0 }
  validates :price, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validate :photo_urls_are_http_urls

  PRICE_UNITS = { "k" => 1_000, "nghìn" => 1_000, "ngàn" => 1_000, "tr" => 1_000_000, "triệu" => 1_000_000 }.freeze

  # Owners type prices like "450.000", "450 000 ₫", "450k" or "1,2tr": drop thousands separators and the
  # currency mark so "." isn't read as a decimal point; a unit multiplies. Anything else is left for validation to reject.
  def price=(value)
    if value.is_a?(String)
      amount, unit = value.downcase.delete(" ").match(/\A(\d+(?:[.,]\d+)?)(#{PRICE_UNITS.keys.join("|")})\z/)&.captures
      value = unit ? (BigDecimal(amount.tr(",", ".")) * PRICE_UNITS[unit]).to_i : value.gsub(/vn[dđ]|[.,\s₫đ]/i, "").presence
    end
    super(value)
  end

  private
    def photo_urls_are_http_urls
      valid = photo_urls.is_a?(Array) && photo_urls.all? { it.is_a?(String) && it.match?(%r{\Ahttps?://\S+\z}) }
      errors.add(:photo_urls, :invalid) unless valid
    end
end
