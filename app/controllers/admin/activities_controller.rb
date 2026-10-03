# Owners and admins: who changed what on a homestay, newest first.
class Admin::ActivitiesController < Admin::BaseController
  PER_PAGE = 50

  def show
    @place = Current.user.accessible_places.find_by!(slug: params[:place_slug])
    authorize!(:manage, @place)
    versions = PaperTrail::Version.where(place_id: @place.id).order(id: :desc)
    versions = versions.where(id: ...params[:before].to_i) if params[:before].present?
    @versions = versions.limit(PER_PAGE).to_a
  end
end
