# Parent of every PMS PWA controller (#228): the scoping rules of PlaceAuthorization (Current.user.accessible_*,
# find / find_by! → 404, authorize! → 403) and the current homestay.
class Pms::BaseController < ApplicationController
  include PlaceAuthorization

  layout "pms"

  rescue_from Forbidden, with: -> { render "pms/forbidden", status: :forbidden, formats: :html }
  rescue_from ActiveRecord::RecordNotFound, with: -> { render "pms/not_found", status: :not_found, formats: :html }

  helper_method :current_place, :places

  # ?co_so=<slug> opens a screen on that homestay: pushes (#237) and the old /admin homestay URLs (#247).
  before_action { session[:pms_place] = params[:co_so] if Current.user && params[:co_so].is_a?(String) && places.exists?(slug: params[:co_so]) }

  private
    def places = Current.user.accessible_places.order(:name)

    # The homestay picked in Thêm, else the first one. nil when the user has none.
    def current_place
      @current_place ||= places.find_by(slug: session[:pms_place]) || places.first
    end
end
