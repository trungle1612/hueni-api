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

  def can_check_in? = check_in_refusal.nil?
  def can_check_out? = checked_in_at.present? && checked_out_at.nil?

  # The guest arrived: a hold becomes confirmed. Returns false with the reason in errors[:base].
  def check_in
    with_lock do
      next refuse(check_in_refusal) unless can_check_in?
      update(checked_in_at: Time.current, status: :confirmed)
    end
  end

  # The guest left: the room needs cleaning. The remaining nights stay booked (edit the dates to resell them).
  def check_out
    with_lock do
      next refuse(checked_in_at ? "Khách đã trả phòng rồi" : "Khách chưa nhận phòng") unless can_check_out?
      update(checked_out_at: Time.current) && room.dirty! && true
    end
  end

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

    def check_in_refusal
      if cancelled? then "Đặt phòng đã huỷ"
      elsif checked_in_at then "Khách đã nhận phòng rồi"
      elsif Date.current < start_date then "Chưa đến ngày nhận phòng"
      elsif Date.current >= end_date then "Đặt phòng đã kết thúc"
      end
    end

    def refuse(reason)
      errors.add(:base, reason)
      false
    end
end
