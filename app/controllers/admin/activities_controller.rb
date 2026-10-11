# Owners: who changed what on a homestay, newest first.
class Admin::ActivitiesController < Admin::BaseController
  PER_PAGE = 50

  def show
    @place = Current.user.accessible_places.find_by!(slug: params[:place_slug])
    authorize!(:manage, @place)
    versions = PaperTrail::Version.where(place_id: @place.id).order(id: :desc)
    before = Integer(params[:before].to_s, exception: false) if params[:before].is_a?(String)
    versions = versions.where(id: ...before) if before&.positive?
    @versions = versions.limit(PER_PAGE).to_a
  end
end
