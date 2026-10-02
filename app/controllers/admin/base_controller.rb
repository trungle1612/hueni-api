# Parent of every /admin controller. Look records up only through Current.user.accessible_*
# with find / find_by! (e.g. Current.user.accessible_rooms.find(params[:id])): out of scope →
# RecordNotFound → 404. Never permit place_id / room_id / calendar_feed_id in params; build
# children through a scoped parent (Current.user.accessible_rooms.find(params[:room_id]).bookings.build).
class Admin::BaseController < ApplicationController
  # Owner-only action on a homestay you can see but don't own (e.g. you're staff there).
  class Forbidden < StandardError; end

  rescue_from Forbidden, with: -> { render "admin/forbidden", status: :forbidden }
  # Out of scope (or gone): a friendly 404 inside the admin layout, also in development.
  rescue_from ActiveRecord::RecordNotFound, with: -> { render "admin/not_found", status: :not_found }

  helper_method :allowed_to?

  private
    def allowed_to?(action, place) = Current.user.allowed_to?(action, place)

    # After the accessible_* lookup (404 when out of scope): 403 when in scope but not allowed.
    def authorize!(action, place)
      raise Forbidden unless allowed_to?(action, place)
    end

    # A YYYY-MM-DD query param, or nil when missing or malformed.
    def date_param(key)
      Date.iso8601(params[key].to_s)
    rescue Date::Error
      nil
    end
end
