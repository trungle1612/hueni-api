# Parent of every PMS PWA controller (#228). Same scoping rules as /admin (Current.user.accessible_*,
# find / find_by! → 404, authorize! → 403); only the layout and the error pages differ.
# ponytail: inherits Admin::BaseController for those rules; extract a shared concern when /admin shrinks (ADR-002).
class Pms::BaseController < Admin::BaseController
  layout "pms"

  rescue_from Forbidden, with: -> { render "pms/forbidden", status: :forbidden, formats: :html }
  rescue_from ActiveRecord::RecordNotFound, with: -> { render "pms/not_found", status: :not_found, formats: :html }

  helper_method :current_place, :places

  private
    def places = Current.user.accessible_places.order(:name)

    # The homestay picked in Thêm, else the first one. nil when the user has none.
    def current_place
      @current_place ||= places.find_by(slug: session[:pms_place]) || places.first
    end
end
