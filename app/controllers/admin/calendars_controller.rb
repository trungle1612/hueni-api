class Admin::CalendarsController < Admin::BaseController
  DAYS = 14

  # Menu entry and place switcher: the picked homestay's calendar, else the first one.
  def index
    places = Current.user.accessible_places
    place = params[:slug] ? places.find_by!(slug: params[:slug]) : places.order(:name).first
    redirect_to place ? admin_place_calendar_path(place.slug) : admin_root_path
  end

  def show
    @place = Current.user.accessible_places.find_by!(slug: params[:place_slug])
    @places = Current.user.accessible_places.order(:name)
    @days = (date_param(:from) || Date.current).then { it...(it + DAYS) }
    @rooms = @place.rooms.where(active: true).order(:name)
    # Loại phòng filter (#138): the types these rooms use, in Room::ROOM_TYPES order.
    @room_types = Room::ROOM_TYPES.keys & @rooms.distinct.pluck(:room_type)
    @room_type = params[:type].presence_in(@room_types)
    @rooms = @rooms.where(room_type: @room_type) if @room_type
    @calendar = RoomCalendar.new(@rooms, @days.begin, @days.end)
    @bookings = @calendar.by_room
    @conflicts = @calendar.conflicts
    @maintenance_conflicts = @calendar.maintenance_conflicts
  end
end
