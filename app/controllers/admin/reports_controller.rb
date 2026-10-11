# Owners: one homestay's month in numbers (see Report).
class Admin::ReportsController < Admin::BaseController
  # Menu entry and homestay switcher: the picked homestay, else the first one you own. Staff own none → dashboard.
  def index
    places = owned_places
    place = params[:slug] ? Current.user.accessible_places.find_by!(slug: params[:slug]) : places.first
    redirect_to place ? admin_place_report_path(place.slug, month: params[:month].presence) : admin_root_path
  end

  def show
    @place = Current.user.accessible_places.find_by!(slug: params[:place_slug])
    authorize!(:manage, @place)
    @places = owned_places
    @report = Report.new(@place, month_param || Date.current)
  end

  private
    def owned_places
      Current.user.accessible_places.where(id: Current.user.place_memberships.where(role: "owner").select(:place_id)).order(:name)
    end

    # A YYYY-MM query param, or nil when missing or malformed.
    def month_param
      Date.strptime(params[:month].to_s, "%Y-%m") if params[:month].is_a?(String)
    rescue Date::Error
      nil
    end
end
