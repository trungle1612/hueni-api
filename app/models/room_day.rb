# What is going on in a room on a given day. The dashboard room board and the homestay page both read this.
class RoomDay
  attr_reader :room, :state, :booking, :next_booking

  def self.for(rooms, date = Date.current)
    rooms = rooms.to_a
    bookings = Booking.blocking.where(room_id: rooms.map(&:id)).includes(:calendar_feed)
      .where("end_date > :date OR (checked_in_at IS NOT NULL AND checked_out_at IS NULL)", date:)
      .order(:start_date, :id).group_by(&:room_id)
    rooms.map { new(it, bookings.fetch(it.id, []), date) }
  end

  def initialize(room, bookings, date)
    bookings.each { it.association(:room).target = room }
    staying = bookings.find { it.checked_in_at && !it.checked_out_at }
    waiting = bookings.select { !it.checked_in_at && it.start_date <= date && date < it.end_date }
    arriving = waiting.find(&:confirmed?) || waiting.first

    @room = room
    @booking = staying || arriving
    @next_booking = bookings.find { it != @booking && !it.checked_in_at && it.start_date >= date }
    @state =
      if !room.active? then :off
      elsif staying then staying.end_date <= date ? :leaving : :occupied
      elsif arriving then arriving.confirmed? ? :arriving : :held
      else :free
      end
  end
end
