# Tổng quan for admins (#85, #247): pending registrations and every homestay's members and failing feeds (platform
# health), no homestay data. A homestay they are a member of opens in the PWA.
class Admin::DashboardController < Admin::BaseController
  def show
    @pending_registrations = RegistrationRequest.pending.count
    @places = Place.includes(place_memberships: :user).order(:name)
    @feed_errors = CalendarFeed.where.not(last_error: nil).joins(:room).group("rooms.place_id").count
  end
end
