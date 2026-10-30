# hueni's plain GET needs no CORS preflight, so the Allow-Origin header is enough.
class V1::VacancyController < V1::BaseController
  rate_limit to: 60, within: 1.minute

  def show
    expires_in 1.minute, public: true
    render json: Vacancy.cached
  end
end
