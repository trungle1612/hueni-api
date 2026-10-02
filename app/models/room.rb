class Room < ApplicationRecord
  belongs_to :place
  has_many :bookings

  after_commit { Vacancy.bust }

  validates :name, presence: true, uniqueness: { scope: :place_id }
  validates :max_guests, numericality: { only_integer: true, greater_than: 0 }
  validates :price, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validate :photo_urls_are_http_urls

  # Owners type prices like "450.000" or "450 000 ₫": drop thousands separators and the currency mark so "."
  # isn't read as a decimal point. Anything else (e.g. "450k") is left for validation to reject.
  def price=(value)
    super(value.is_a?(String) ? value.gsub(/vn[dđ]|[.,\s₫đ]/i, "").presence : value)
  end

  private
    def photo_urls_are_http_urls
      valid = photo_urls.is_a?(Array) && photo_urls.all? { it.is_a?(String) && it.match?(%r{\Ahttps?://\S+\z}) }
      errors.add(:photo_urls, :invalid) unless valid
    end
end
