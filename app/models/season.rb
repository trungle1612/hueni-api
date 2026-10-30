# Mùa và ngày lễ (#163): + pct on every night from `from` to `to` (inclusive), owner-set. Only new nights take it:
# a booking keeps the season % its nights were booked at (Booking#season_percent_on).
class Season < ApplicationRecord
  belongs_to :place
  has_paper_trail on: %i[create update destroy], only: %i[name start_date end_date percent], meta: { place_id: :place_id }

  # The Mini App's names (Season type); the columns avoid SQL keywords.
  alias_attribute :from, :start_date
  alias_attribute :to, :end_date
  alias_attribute :pct, :percent

  normalizes :name, with: ->(value) { value.squish.presence }
  validates :name, presence: true, length: { maximum: 50 }
  validates :from, :to, presence: true
  validates :pct, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 200 }
  validate -> { errors.add(:to, "phải từ ngày bắt đầu trở đi") if to < from }, if: -> { from && to }

  scope :covering, ->(date) { where(start_date: ..date, end_date: date..) }
end
