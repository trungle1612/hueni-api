# Hôm nay / Ngày mai (#142) for a set of rooms: who leaves, which rooms need cleaning, who arrives, who is in,
# and Cần xử lý. Tổng quan passes every room the user can see; the Mini App (#153) one homestay's.
# Ngày mai: the same lists for tomorrow; Cần xử lý stays today's.
class Today
  # booking: the row to open; date: the day a calendar link should start at (OTA conflicts only).
  Issue = Data.define(:kind, :title, :detail, :booking, :date)

  # date: the day the lists are for (today, or tomorrow for Ngày mai).
  attr_reader :date, :arrivals, :departures, :in_house, :dirty_rooms, :issues

  def initialize(rooms, tomorrow: false)
    today = @date = Date.current
    bookings = Booking.where(room_id: rooms.select(:id)).includes(:calendar_feed, room: :place).order(:start_date, :id)
    @departures = bookings.in_house.where(end_date: ..today).to_a
    @dirty_rooms = rooms.dirty.includes(:place).order(:name).to_a
    @arrivals = bookings.blocking.not_checked_in.where(start_date: ..today, end_date: Booking.arrival_date.next_day..).to_a
    @in_house = bookings.in_house.where(end_date: today.next_day..).to_a
    @issues = conflicts(bookings) + dirty_arrivals + undeclared
    return unless tomorrow

    tomorrow = @date = today.next_day
    @arrivals = bookings.blocking.not_checked_in.where(start_date: tomorrow).to_a
    @departures = bookings.blocking.where(checked_out_at: nil, end_date: tomorrow).to_a
    @dirty_rooms = @departures.map(&:room).uniq.sort_by(&:name)
    @in_house = bookings.blocking_on(tomorrow).where(start_date: ...tomorrow).to_a
  end

  private
    # OTA conflicts from today on.
    def conflicts(bookings)
      upcoming = bookings.blocking.where(end_date: Date.current.next_day..).to_a
      upcoming.select(&:ical?).flat_map do |ical|
        upcoming.select { it.manual? && it.room_id == ical.room_id && it.overlaps?(ical) }.map do |manual|
          date = [ ical.start_date, manual.start_date ].max
          Issue.new(:error, "Trùng lịch OTA", "#{ical.label} và #{manual.label} · Phòng #{manual.room.name} · #{date.strftime("%d/%m")}", manual, date)
        end
      end
    end

    def dirty_arrivals
      @arrivals.select { it.room.dirty? }.map do |booking|
        Issue.new(:clean, "Khách đến, phòng chưa dọn", "#{booking.label} · Phòng #{booking.room.name}", booking, nil)
      end
    end

    def undeclared
      (@departures + @in_house).select(&:needs_declaration?).map do |booking|
        Issue.new(:stay, "Chưa khai báo lưu trú", "#{booking.label} · Phòng #{booking.room.name}", booking, nil)
      end
    end
end
