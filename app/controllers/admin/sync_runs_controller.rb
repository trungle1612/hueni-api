# Admin only (#92): every iCal sync run, newest first. Cross-homestay ops view, so it names the room
# (an agreed exception to #85) but never shows guests, booking dates or feed URLs.
class Admin::SyncRunsController < Admin::BaseController
  PER_PAGE = 50

  before_action { raise ActiveRecord::RecordNotFound unless Current.user.admin? }

  def index
    @places = Place.joins(rooms: :calendar_feeds).distinct.order(:name)
    @place = @places.find_by(slug: params[:place]) if params[:place].is_a?(String)
    @failed_only = params[:failed] == "1"

    runs = SyncRun.includes(calendar_feed: { room: :place }).order(id: :desc)
    runs = runs.joins(calendar_feed: :room).where(rooms: { place_id: @place.id }) if @place
    runs = runs.where(ok: false) if @failed_only
    before = Integer(params[:before].to_s, exception: false) if params[:before].is_a?(String)
    runs = runs.where(id: ...before) if before&.positive?
    @runs = runs.limit(PER_PAGE).to_a
  end
end
