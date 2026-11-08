# Thông báo (#213): the signed-in member's inbox at one homestay (Notification) and their read marks.
class MiniApp::V1::NotificationsController < MiniApp::V1::BaseController
  before_action { @place = Current.user.accessible_places.find(params[:place_id]) }

  def index
    items = Notification.for(Current.user, @place)
    render json: { notifications: items.map(&:to_h), unread: items.count(&:unread), action: items.count { it.unread && it.urgent } }
  end

  # { keys: [] }: tapped, or Đọc hết.
  def read
    NotificationRead.mark(Current.user, NotificationRead.keys(params[:keys]))
    head :no_content
  end

  # { keys: [] }: Hoàn tác after Đọc hết.
  def unread
    Current.user.notification_reads.where(key: NotificationRead.keys(params[:keys])).delete_all
    head :no_content
  end
end
