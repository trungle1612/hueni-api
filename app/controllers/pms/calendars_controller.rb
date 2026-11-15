# Lịch phòng (#230): a week of the current homestay's open rooms from ?from= (default today), from RoomCalendar like /admin.
class Pms::CalendarsController < Pms::BaseController
  DAYS = 7

  def show
    return unless current_place
    @days = (date_param(:from) || Date.current).then { it...(it + DAYS) }
    @rooms = current_place.rooms.where(active: true).order(:name).to_a
    @calendar = RoomCalendar.new(@rooms, @days.begin, @days.end)
  end
end
