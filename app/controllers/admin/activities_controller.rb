# Owners: who changed what on a homestay, newest first.
class Admin::ActivitiesController < Admin::BaseController
  PER_PAGE = Activity::PER_PAGE

  def show
    @place = Current.user.accessible_places.find_by!(slug: params[:place_slug])
    authorize!(:manage, @place)
    @versions = Activity.page(PaperTrail::Version.where(place_id: @place.id), params[:before])
  end
end
