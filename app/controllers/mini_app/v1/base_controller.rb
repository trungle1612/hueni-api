# Zalo Mini App API (#119 C): JSON under /app/v1 with a bearer token from POST /app/v1/session (#152).
# Same access rules as /admin (see Admin::BaseController): look up through Current.user.accessible_*, then authorize!.
# Any origin may call it: there are no cookies, only the token.
class MiniApp::V1::BaseController < ActionController::API
  class Forbidden < StandardError; end

  before_action :allow_cors
  before_action :authenticate, except: :preflight

  rescue_from Forbidden, with: -> { render json: { error: "forbidden", message: "Bạn không có quyền làm việc này." }, status: :forbidden }
  rescue_from ActiveRecord::RecordNotFound, with: -> { render json: { error: "not_found" }, status: :not_found }

  # CORS preflight for every /app/v1 path.
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

    def allow_cors
      response.headers["Access-Control-Allow-Origin"] = "*"
      response.headers["Access-Control-Allow-Headers"] = "Authorization, Content-Type, X-Registration-Token"
      response.headers["Access-Control-Allow-Methods"] = "GET, POST, PATCH, DELETE, OPTIONS"
      response.headers["Access-Control-Max-Age"] = "86400"
    end
end
