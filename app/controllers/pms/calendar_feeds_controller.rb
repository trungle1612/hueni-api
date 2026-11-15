# A room's iCal link on Kênh bán phòng (#246): Kết nối (owners, syncs inline so
# the owner sees straight away whether the link works), Đồng bộ ngay (staff too), Ngắt kết nối (owners).
# Never echo the URL: it carries the OTA's token.
class Pms::CalendarFeedsController < Pms::BaseController
  before_action :set_feed, only: %i[sync destroy]

  def create
    room = Current.user.accessible_rooms.find(params[:room_id])
    authorize!(:manage, room.place)
    feed = room.calendar_feeds.build(params.expect(calendar_feed: %i[provider url]))
    if !feed.save
      redirect_to pms_channels_path, status: :see_other, alert: feed.errors.full_messages.to_sentence
    elsif feed.sync(trigger: "added")
      redirect_to pms_channels_path, status: :see_other, flash: { toast: "#{feed.provider_label} đã đọc được lịch phòng #{room.name}" }
    else
      redirect_to pms_channels_path, status: :see_other, alert: "Đã kết nối phòng #{room.name}, nhưng đồng bộ lỗi. #{feed.error_message}"
    end
  end

  def sync
    authorize!(:operate, @feed.room.place)
    if @feed.synced_recently?
      redirect_to pms_channels_path, status: :see_other, alert: "Vừa đồng bộ, thử lại sau 1 phút."
    elsif @feed.sync
      redirect_to pms_channels_path, status: :see_other, flash: { toast: "Đã đồng bộ #{@feed.provider_label} phòng #{@feed.room.name}" }
    else
      redirect_to pms_channels_path, status: :see_other, alert: "Đồng bộ lỗi. #{@feed.error_message}"
    end
  end

  def destroy
    authorize!(:manage, @feed.room.place)
    @feed.destroy!
    redirect_to pms_channels_path, status: :see_other,
      flash: { toast: "Đã ngắt #{@feed.provider_label} phòng #{@feed.room.name}. Phòng không còn chặn theo lịch kênh này." }
  end

  private
    def set_feed
      @feed = Current.user.accessible_calendar_feeds.find(params[:id])
    end
end
