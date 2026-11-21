# Thông báo (#237, board Notifications.dc.html): the current homestay's Notification.for the signed-in member, staff
# and owners alike (what each sees is decided there). Tapping one marks it read and opens what it is about; a push
# opens the same URL with ?co_so= so it lands on the homestay it came from.
class Pms::NotificationsController < Pms::BaseController
  FILTERS = %w[chua-doc can-xu-ly].freeze

  before_action(except: :show) { redirect_to pms_today_path unless current_place }

  def show
    return unless current_place
    @items = Notification.for(Current.user, current_place)
    @filter = params[:loc].presence_in(FILTERS)
    @announcement = @items.find { it.announcement && it.key == params[:xem] }
  end

  def open
    item = Notification.for(Current.user, current_place).find { it.key == params[:key] }
    return redirect_to pms_notifications_path unless item
    NotificationRead.mark(Current.user, [ item.key ])
    redirect_to item.announcement ? pms_notifications_path(xem: item.key) : target(item.link) || pms_notifications_path
  end

  def read_all
    at = Time.current
    keys = Notification.for(Current.user, current_place).select(&:unread).map(&:key)
    NotificationRead.mark(Current.user, keys, at:)
    redirect_to pms_notifications_path(loc: params[:loc].presence_in(FILTERS)),
      flash: { toast: "Đã đánh dấu #{keys.size} thông báo là đã đọc", read_at: (at.iso8601(6) if keys.any?) }
  end

  # Hoàn tác in the toast: what Đọc hết marked (this user's reads since then).
  def undo_read
    at = (Time.zone.iso8601(params[:at].to_s) rescue nil)
    Current.user.notification_reads.where(created_at: at..).delete_all if at
    redirect_to pms_notifications_path(loc: params[:loc].presence_in(FILTERS))
  end

  # Cài đặt thông báo: the types left on (Trùng phòng và lỗi kênh always is) and Giờ yên lặng, for this account.
  def settings
    Current.user.update!(notifications_off: Notification::OPTIONAL - Array(params[:on]), quiet_hours: params[:quiet] == "1")
    redirect_to pms_notifications_path(loc: params[:loc].presence_in(FILTERS), "cai-dat": 1)
  end

  private
    # Where a notification's link opens in the PWA; nil for a screen it does not have yet (Giao ca).
    def target(link)
      case link&.dig(:screen)
      when "booking" then pms_booking_path(link[:id]) if link[:id]
      when "channels" then pms_channels_path
      when "housekeeping" then pms_rooms_path
      when "approvals" then pms_members_path
      when "requests" then pms_booking_requests_path
      when "today" then pms_today_path
      end
    end
end
