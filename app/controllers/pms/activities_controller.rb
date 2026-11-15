# Nhật ký (#245), owners only: the current homestay's changes, newest first, Activity::PER_PAGE at a time,
# filters Huỷ · Giá · Tiền (Activity::FILTERS), like the Mini App.
class Pms::ActivitiesController < Pms::BaseController
  def show
    return unless current_place
    authorize!(:manage, current_place)
    @filter = params[:filter].presence_in(Activity::FILTERS.keys)
    @versions = Activity.page(Activity.filter(PaperTrail::Version.where(place_id: current_place.id), @filter), params[:before])
  end
end
