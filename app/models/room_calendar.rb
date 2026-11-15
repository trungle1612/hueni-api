# Lịch phòng: the bookings drawn on rooms × from...to (to exclusive) and the overlaps the owner has to resolve.
# One source for the /admin calendar, the PWA (#230) and /api/v1 places#calendar.
class RoomCalendar
  attr_reader :bookings, :conflicts, :maintenance_conflicts

  def initialize(rooms, from, to)
    # In-house guests too: an overdue one still holds the room, one due out today is listed by the room name.
    @bookings = Booking.blocking.where(room: rooms).merge(Booking.overlapping(from, to).or(Booking.in_house))
      .includes(:calendar_feed, :room, :payments).order(:start_date, :id).to_a
    # The OTA already sold an iCal booking's nights, so an overlap with a manual one is for the owner to resolve: [ical, manual].
    @conflicts = @bookings.select(&:ical?).flat_map do |ical|
      @bookings.select { it.manual? && it.room_id == ical.room_id && it.overlaps?(ical) }.map { [ ical, it ] }
    end
    # Bookings made before a Bảo trì was set on their room stay; the owner moves or cancels them.
    @maintenance_conflicts = @bookings.select(&:in_maintenance?)
  end

  def by_room = bookings.group_by(&:room_id)
  def conflict_ids = (conflicts.flatten + maintenance_conflicts).to_set(&:id)
end
