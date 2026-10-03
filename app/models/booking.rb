class Booking < ApplicationRecord
  belongs_to :room
  belongs_to :calendar_feed, optional: true

  after_commit { Vacancy.bust }

  enum :status, { hold: "hold", confirmed: "confirmed", cancelled: "cancelled" }, validate: true
  enum :source, { manual: "manual", ical: "ical" }, validate: true

  validates :start_date, presence: true
  validates :end_date, presence: true, comparison: { greater_than: :start_date }, if: :start_date
  # iCal bookings skip this: the OTA already sold those nights, so an overlap is shown as a conflict instead.
  validate :room_is_free, if: -> { manual? && (hold? || confirmed?) && room && start_date && end_date }
  validate :guests_fit_room, if: -> { guests && room }
  validate :not_cancelled_after_check_in, if: -> { cancelled? && checked_in_at }

  # Holds and confirmed stays occupy the room from start_date up to, not including, end_date.
  scope :blocking, -> { where(status: [ :hold, :confirmed ]) }
  scope :blocking_on, ->(date) { blocking.where(start_date: ..date, end_date: date.next_day..) }
  # Bookings occupying any night in from...to (to exclusive).
  scope :overlapping, ->(from, to) { where(start_date: ...to, end_date: from.next_day..) }
  scope :in_house, -> { where.not(checked_in_at: nil).where(checked_out_at: nil) }
  scope :not_checked_in, -> { where(checked_in_at: nil) }

  def overlaps?(other) = start_date < other.end_date && other.start_date < end_date

  private
    def room_is_free
      taken = room.bookings.blocking.overlapping(start_date, end_date).where.not(id: id).exists?
      errors.add(:base, "Phòng đã có người đặt trong khoảng ngày này") if taken
    end
    def guests_fit_room
      errors.add(:base, "Số khách phải từ 1 đến #{room.max_guests}") unless guests.in?(1..room.max_guests)
    end

    def not_cancelled_after_check_in
      errors.add(:base, "Khách đã nhận phòng, không huỷ được")
    end
end
