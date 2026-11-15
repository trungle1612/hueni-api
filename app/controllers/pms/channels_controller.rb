# Kênh bán phòng (#246, board Channels.dc.html): the current homestay's iCal links grouped by OTA, recent syncs and
# Đồng bộ tất cả for anyone at the desk; Hoa hồng for owners. Links are added / synced / removed in
# Pms::CalendarFeedsController. Same model rules as the Mini App.
class Pms::ChannelsController < Pms::BaseController
  before_action -> { authorize!(:operate, current_place) if current_place }, only: :show
  before_action :set_place, only: %i[sync commissions]
  before_action -> { authorize!(:operate, @place) }, only: :sync
  before_action -> { authorize!(:manage, @place) }, only: :commissions

  def show
    return unless (place = current_place)
    @rooms = place.rooms.includes(:calendar_feeds).order(:name)
    feeds = @rooms.flat_map(&:calendar_feeds)
    @feeds = feeds.group_by(&:provider)
    @bookings = Booking.joins(:calendar_feed).where(calendar_feed: feeds, start_date: Date.current.all_month).group("calendar_feeds.provider").count
    @runs = SyncRun.where(calendar_feed: feeds).includes(calendar_feed: :room).order(started_at: :desc).limit(5)
  end

  # Đồng bộ ngay at the bottom: queued (Place#sync_feeds), each link may take up to CalendarFeed::TIMEOUT seconds.
  def sync
    count = @place.sync_feeds
    toast = count.positive? ? "Đang đồng bộ #{count} link. Tải lại trang sau ít phút." : "Vừa đồng bộ, thử lại sau 1 phút."
    redirect_to pms_channels_path, status: :see_other, flash: { toast: }
  end

  # One OTA's % from its sheet; the others stay as they are.
  def commissions
    if @place.update(commissions: @place.commissions.merge(params.expect(place: [ commissions: Place::COMMISSION_PROVIDERS ])[:commissions].to_h))
      redirect_to pms_channels_path, status: :see_other, flash: { toast: "Đã lưu hoa hồng" }
    else
      redirect_to pms_channels_path, status: :see_other, alert: "Hoa hồng #{@place.errors.messages_for(:commissions).to_sentence}."
    end
  end

  private
    def set_place
      @place = current_place or raise ActiveRecord::RecordNotFound
    end
end
