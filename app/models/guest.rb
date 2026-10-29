# Hồ sơ khách (#165), per homestay. A guest is the direct bookings sharing a key: the phone digits (Booking.search_digits),
# else the folded name. OTA bookings carry neither, so they have no profile. No merge: a new phone is a new guest.
# The row holds Ghi chú cho lễ tân and Cần lưu ý (flag = the reason, shown to staff too); flagging is logged.
class Guest < ApplicationRecord
  belongs_to :place
  has_paper_trail only: %i[name flag], meta: { place_id: :place_id }, if: ->(guest) { guest.will_save_change_to_flag? || guest.saved_change_to_flag? }

  normalizes :note, with: ->(value) { value.strip.presence }
  normalizes :flag, with: ->(value) { value.squish.presence }
  validates :key, presence: true
  validates :note, length: { maximum: 1000 }
  validates :flag, length: { maximum: 200 }

  def self.key_for(booking)
    return unless booking.manual?
    Booking.search_digits(booking.guest_phone).presence || Booking.search_fold(booking.guest_name).presence
  end

  # The profile of the guest of this booking (a new, unsaved one when nothing was kept yet), or nil without a key.
  def self.of(booking)
    key = key_for(booking) or return
    find_or_initialize_by(place_id: booking.room.place_id, key:)
  end

  # Every direct booking of this homestay, grouped by guest key: { key => [bookings, newest first] }.
  def self.stays(place)
    Booking.manual.where(room: place.rooms).includes(:room, :charges, :payments).order(start_date: :desc, id: :desc)
      .group_by { key_for(it) }.except(nil)
  end

  attr_writer :bookings
  def bookings = @bookings ||= Guest.stays(place).fetch(key, [])

  # The newest booking names the guest, so a corrected name or phone shows.
  def latest = bookings.first
  def visits = bookings.select(&:confirmed?)
  def returning? = visits.size > 1
  def paid = bookings.sum(&:paid)
  def due = visits.sum { [ it.due.to_i, 0 ].max }

  # Saved with the guest's current name, which Hoạt động shows (never the phone).
  def save_details(attributes)
    assign_attributes(attributes)
    self.name = latest&.guest_name
    save
  end
end
