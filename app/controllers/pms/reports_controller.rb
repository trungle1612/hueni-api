# Báo cáo (#234): the current homestay's Report, the same numbers as /admin; owners and staff with the report right.
# bao-cao.csv = Xuất CSV.
class Pms::ReportsController < Pms::BaseController
  def show
    return unless current_place
    authorize!(:report, current_place)
    @report = Report.for(current_place, period: params[:period], month: params[:month])
    send_data @report.to_csv, type: "text/csv; charset=utf-8", filename: @report.csv_filename if request.format.csv?
  end
end
