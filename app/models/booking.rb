class Booking < ApplicationRecord
  belongs_to :room

  after_commit { Vacancy.bust }

  enum :status, { hold: "hold", confirmed: "confirmed", cancelled: "cancelled" }, validate: true
  enum :source, { manual: "manual", ical: "ical" }, validate: true

  validates :start_date, presence: true
  validates :end_date, presence: true, comparison: { greater_than: :start_date }, if: :start_date

  # Holds and confirmed stays occupy the room from start_date up to, not including, end_date.
  scope :blocking, -> { where(status: [ :hold, :confirmed ]) }
  scope :blocking_on, ->(date) { blocking.where(start_date: ..date, end_date: date.next_day..) }
end
