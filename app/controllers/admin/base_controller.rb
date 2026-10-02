# Parent of every /admin controller. Look records up only through Current.user.accessible_*
# with find / find_by! (e.g. Current.user.accessible_rooms.find(params[:id])): out of scope →
# RecordNotFound → 404. Never permit place_id / room_id / calendar_feed_id in params; build
# children through a scoped parent (Current.user.accessible_rooms.find(params[:room_id]).bookings.build).
class Admin::BaseController < ApplicationController
  private
    # A YYYY-MM-DD query param, or nil when missing or malformed.
    def date_param(key)
      Date.iso8601(params[key].to_s)
    rescue Date::Error
      nil
    end
end
