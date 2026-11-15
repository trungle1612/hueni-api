# Homestay rights for the PMS PWA (#228, #247). Look records up only through Current.user.accessible_* with find / find_by!
# (e.g. Current.user.accessible_rooms.find(params[:id])): out of scope → RecordNotFound → 404. Never permit place_id / room_id /
# calendar_feed_id in params; build children through a scoped parent. In scope but not allowed → authorize! → Forbidden → 403.
module PlaceAuthorization
  extend ActiveSupport::Concern

  # Owner-only action on a homestay you can see but don't own (e.g. you're staff there).
  class Forbidden < StandardError; end

  included do
    helper_method :allowed_to?
  end

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
