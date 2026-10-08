# What is going on in a room on a given day. The dashboard room board and the homestay page both read this.
class RoomDay
  attr_reader :room, :state, :booking, :next_booking

  def self.for(rooms, date = Date.current)
    rooms = rooms.to_a
    arrival_date = date == Date.current ? Booking.arrival_date : date
    bookings = Booking.blocking.where(room_id: rooms.map(&:id)).includes(:calendar_feed)
      .where("end_date > :arrival_date OR (checked_in_at IS NOT NULL AND checked_out_at IS NULL)", arrival_date:)
      .order(:start_date, :id).group_by(&:room_id)
    rooms.map { new(it, bookings.fetch(it.id, []), date, arrival_date) }
  end

  # arrival_date: the day whose late arrivals are still expected (Booking.arrival_date), so a guest due
  # yesterday shows as Chờ khách until Booking::LATE_ARRIVAL_UNTIL.
  def initialize(room, bookings, date, arrival_date = date)
    bookings.each { it.association(:room).target = room }
    staying = bookings.find { it.checked_in_at && !it.checked_out_at }
    waiting = bookings.select { !it.checked_in_at && it.start_date <= date && arrival_date < it.end_date }
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
