# Zalo Mini App API (#119 C): JSON under /api/v1 with a bearer token from POST /api/v1/session (#152).
# Same access rules as /admin (see Admin::BaseController): look up through Current.user.accessible_*, then authorize!.
# Any origin may call it: there are no cookies, only the token.
class MiniApp::V1::BaseController < ActionController::API
  class Forbidden < StandardError; end

  before_action :allow_cors
  before_action :authenticate, except: :preflight
  before_action :set_paper_trail_whodunnit, except: :preflight # after authenticate: the user, see user_for_paper_trail

  rescue_from Forbidden, with: -> { render json: { error: "forbidden", message: "Bạn không có quyền làm việc này." }, status: :forbidden }
  rescue_from ActiveRecord::RecordNotFound, with: -> { render json: { error: "not_found" }, status: :not_found }
  rescue_from ActionController::ParameterMissing, with: -> { render json: { error: "bad_request", message: "Thiếu dữ liệu gửi lên." }, status: :bad_request }

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

    # Each request reads or changes one homestay, @place.
    def manage? = Current.user.allowed_to?(:manage, @place)

    # Serializer params: staff never get the nightly quote or the owner's room note (same as /admin).
    def serializer_params = { manage: manage? }

    # Every change answers with the booking as it is now, like GET /bookings/:id.
    def render_booking(booking, status: :ok)
      booking = Booking.includes(:calendar_feed, :charges, payments: :user).find(booking.id)
      render json: MiniApp::BookingDetailSerializer.new(booking, params: serializer_params), status:
    end

    # Validation errors and refusals: errors per field (base = not about one field), Vietnamese full messages.
    def render_invalid(record)
      render json: { error: "invalid", message: record.errors.full_messages.to_sentence, errors: record.errors.to_hash(true) },
        status: :unprocessable_entity
    end

    def allow_cors
      response.headers["Access-Control-Allow-Origin"] = "*"
      response.headers["Access-Control-Allow-Headers"] = "Authorization, Content-Type, X-Registration-Token"
      response.headers["Access-Control-Allow-Methods"] = "GET, POST, PATCH, DELETE, OPTIONS"
      response.headers["Access-Control-Max-Age"] = "86400"
    end
end
