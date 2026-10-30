# Public, unauthenticated /v1 for hueni.me. Not ApplicationController: allow_browser would block curl and uptime checks.
# CORS for hueni's origins only; the booking page's JSON POST gets a preflight answer here.
class V1::BaseController < ActionController::API
  ALLOWED_ORIGINS = %w[https://hueni.me http://localhost:5173].freeze

  before_action :allow_cors

  def preflight
    response.headers["Access-Control-Allow-Methods"] = "GET, POST"
    response.headers["Access-Control-Allow-Headers"] = "Content-Type"
    response.headers["Access-Control-Max-Age"] = "3600"
    head :no_content
  end

  private
    def allow_cors
      response.headers["Vary"] = "Origin"
      origin = request.headers["Origin"]
      response.headers["Access-Control-Allow-Origin"] = origin if ALLOWED_ORIGINS.include?(origin)
    end
end
