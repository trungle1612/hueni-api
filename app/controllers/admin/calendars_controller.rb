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
    bookings = Booking.blocking.overlapping(@days.begin, @days.end).where(room: @rooms).includes(:calendar_feed).order(:start_date).to_a
    @bookings = bookings.group_by(&:room_id)
    # The OTA already sold an iCal booking's nights, so an overlap with a manual one is for the owner to resolve.
    @conflicts = bookings.select(&:ical?).flat_map do |ical|
      bookings.select { it.manual? && it.room_id == ical.room_id && it.overlaps?(ical) }.map { [ ical, it ] }
    end
  end
end
