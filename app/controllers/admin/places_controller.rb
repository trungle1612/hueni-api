class Admin::PlacesController < Admin::BaseController
  def show
    @place = Current.user.accessible_places.find_by!(slug: params[:slug])
    @days = RoomDay.for(@place.rooms.order(active: :desc, name: :asc)) # switched-off rooms last
    @vacancy_left = Vacancy.cached[:places].dig(@place.slug, :left)
    @feed_errors = CalendarFeed.where(room: @place.rooms).where.not(last_error: nil).count
    @memberships = @place.place_memberships.includes(:user).sort_by { [ it.owner? ? 0 : 1, it.user.name ] } if allowed_to?(:manage, @place)
  end
end
