# Public, unauthenticated. hueni's plain GET needs no CORS preflight, so the header below is enough.
class V1::VacancyController < ActionController::API
  ALLOWED_ORIGINS = %w[https://hueni.me http://localhost:5173].freeze

  rate_limit to: 60, within: 1.minute

  def show
    allow_cors
    expires_in 1.minute, public: true
    render json: Vacancy.cached
  end

  private
    def allow_cors
      response.headers["Vary"] = "Origin"
      origin = request.headers["Origin"]
      response.headers["Access-Control-Allow-Origin"] = origin if ALLOWED_ORIGINS.include?(origin)
    end
end
