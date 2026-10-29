# Owners: one homestay's month, or last 7 days, in numbers (see Report); Xuất CSV as report.csv.
class Admin::ReportsController < Admin::BaseController
  # Menu entry and homestay switcher: the picked homestay, else the first one you own. Staff own none → dashboard.
  def index
    places = owned_places
    place = params[:slug] ? Current.user.accessible_places.find_by!(slug: params[:slug]) : places.first
    redirect_to place ? admin_place_report_path(place.slug, month: params[:month].presence, period: params[:period].presence_in(%w[7d])) : admin_root_path
  end

  def show
    @place = Current.user.accessible_places.find_by!(slug: params[:place_slug])
    authorize!(:report, @place)
    @places = owned_places
    @report = params[:period] == "7d" ? Report.week(@place) : Report.new(@place, month_param || Date.current)
    respond_to do |format|
      format.html
      format.csv do
        send_data @report.to_csv, type: "text/csv; charset=utf-8",
          filename: "bao-cao-#{@place.slug}-#{@report.first.iso8601}-#{@report.last.iso8601}.csv"
      end
    end
  end

  private
    # A YYYY-MM query param, or nil when missing or malformed.
    def month_param
      Date.strptime(params[:month].to_s, "%Y-%m") if params[:month].is_a?(String)
    rescue Date::Error
      nil
    end
end
