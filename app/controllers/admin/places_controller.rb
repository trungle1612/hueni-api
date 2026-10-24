class Admin::PlacesController < Admin::BaseController
  before_action :set_place
  before_action -> { authorize!(:operate, @place) }, only: :sync_feeds
  before_action -> { authorize!(:manage, @place) }, only: :commissions

  def show
    @days = RoomDay.for(@place.rooms.order(active: :desc, name: :asc)) # switched-off rooms last
    @vacancy_left = Vacancy.cached[:places].dig(@place.slug, :left)
    @feed_errors = CalendarFeed.where(room: @place.rooms).where.not(last_error: nil).count
    @memberships = @place.place_memberships.includes(:user).sort_by { [ it.owner? ? 0 : 1, it.user.name ] } if allowed_to?(:manage, @place)
  end

  # Đồng bộ tất cả (#125): queued, since each link may take up to CalendarFeed::TIMEOUT seconds.
  def sync_feeds
    feeds = CalendarFeed.where(room: @place.rooms).reject(&:synced_recently?)
    feeds.each { SyncCalendarFeedJob.perform_later(it.id, "manual") }
    notice = feeds.any? ? "Đang đồng bộ #{feeds.size} kênh của #{@place.name}. Tải lại trang sau ít phút." : "Vừa đồng bộ, thử lại sau 1 phút."
    redirect_back_or_to admin_calendar_feeds_path, notice:
  end

  def commissions
    if @place.update(commissions: params.expect(place: [ commissions: Place::COMMISSION_PROVIDERS ])[:commissions])
      redirect_to admin_calendar_feeds_path(anchor: @place.slug), notice: "Đã lưu hoa hồng của #{@place.name}."
    else
      redirect_to admin_calendar_feeds_path(anchor: @place.slug), alert: "Hoa hồng #{@place.errors.messages_for(:commissions).to_sentence}."
    end
  end

  private
    def set_place
      @place = Current.user.accessible_places.find_by!(slug: params[:slug])
    end
end
