# Zalo Mini App API (#119 C): JSON under /api/v1 with a bearer token from POST /api/v1/session (#152).
# Same access rules as /admin (see Admin::BaseController): look up through Current.user.accessible_*, then authorize!.
# Any origin may call it: there are no cookies, only the token.
class MiniApp::V1::BaseController < ActionController::API
  class Forbidden < StandardError; end

  before_action :allow_cors
  before_action :authenticate, except: :preflight

  rescue_from Forbidden, with: -> { render json: { error: "forbidden", message: "Bạn không có quyền làm việc này." }, status: :forbidden }
  rescue_from ActiveRecord::RecordNotFound, with: -> { render json: { error: "not_found" }, status: :not_found }

  # CORS preflight for every /api/v1 path.
  def preflight = head(:no_content)

  private
    def authenticate
      Current.api_token = ApiToken.authenticate(request.authorization.to_s[/\ABearer (\S+)\z/, 1])
      render json: { error: "unauthorized", message: "Phiên đăng nhập đã hết hạn. Đăng nhập lại bằng Zalo." }, status: :unauthorized unless Current.api_token
    end

    def authorize!(action, place)
      raise Forbidden unless Current.user.allowed_to?(action, place)
    end

    def user_for_paper_trail = Current.user&.id

    # The Mini App's Place type: { id, slug, name, role }.
    def me_json(user)
      places = user.accessible_places.order(:name).to_a
      roles = user.place_memberships.to_h { [ it.place_id, it.role ] }
      { user: { id: user.id, name: user.name }, places: places.map { { id: it.id, slug: it.slug, name: it.name, role: roles[it.id] } } }
    end

    def date_param(key)
      Date.iso8601(params[key].to_s)
    rescue Date::Error
      nil
    end

    # Staff never get the nightly quote or the owner's room note (same as /admin). Each request reads one homestay, @place.
    def manage? = @manage.nil? ? (@manage = Current.user.allowed_to?(:manage, @place)) : @manage

    # The Mini App's Room type. maintenance.until is the last blocked day (inclusive, Room#maintenance_on?).
    def room_json(room)
      json = room.slice(:id, :place_id, :name, :max_guests, :active, :housekeeping, :floor)
      json[:kind] = Room::ROOM_TYPES[room.room_type]
      json[:amenities] = room.amenities.map { Room::AMENITIES[it] }
      json[:maintenance] = { reason: room.maintenance_reason, until: room.maintenance_until } if room.maintenance?
      json.merge!(room.slice(:price, :weekend_price, :note)) if manage?
      json
    end

    # The Mini App's Booking type. Callers preload :calendar_feed and :payments (awaiting_deposit reads payments).
    def booking_json(booking)
      json = booking.slice(:id, :room_id, :start_date, :end_date, :status, :source, :guest_name, :guest_phone, :guests, :note,
        :cancel_reason, :checked_in_at, :checked_out_at, :declared_at, :removed_from_feed_at)
      json[:code] = booking.code
      json[:label] = booking.label
      json[:provider] = booking.calendar_feed&.provider
      json[:discount] = { amount: booking.discount, reason: booking.discount_reason } if booking.discount
      json[:awaiting_deposit] = booking.awaiting_deposit?
      json.merge!(booking.slice(:price, :weekend_price)) if manage?
      json
    end

    def allow_cors
      response.headers["Access-Control-Allow-Origin"] = "*"
      response.headers["Access-Control-Allow-Headers"] = "Authorization, Content-Type, X-Registration-Token"
      response.headers["Access-Control-Allow-Methods"] = "GET, POST, PATCH, DELETE, OPTIONS"
      response.headers["Access-Control-Max-Age"] = "86400"
    end
end
