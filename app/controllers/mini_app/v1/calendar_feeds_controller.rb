# Đồng bộ ngay for one OTA feed (#157), like Admin::CalendarFeedsController#sync: owners and staff, inline so the
# answer says straight away whether the link works. Adding / removing feeds stays on the web.
class MiniApp::V1::CalendarFeedsController < MiniApp::V1::BaseController
  def sync
    feed = Current.user.accessible_calendar_feeds.find(params[:id])
    authorize!(:operate, @place = feed.room.place)
    if feed.synced_recently?
      render json: { error: "rate_limited", message: "Vừa đồng bộ, thử lại sau 1 phút." }, status: :too_many_requests
    elsif feed.sync
      render json: MiniApp::FeedSerializer.new(feed)
    else
      render json: { error: "sync_failed", message: "Đồng bộ lỗi. #{feed.error_message}", feed: MiniApp::FeedSerializer.new(feed) }, status: :unprocessable_entity
    end
  end
end
