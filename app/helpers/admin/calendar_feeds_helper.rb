module Admin::CalendarFeedsHelper
  def feed_status_badge(feed)
    label, color =
      if feed.last_error then [ "Lỗi #{time_ago_in_words(feed.last_error_at)} trước", "badge-error" ]
      elsif feed.last_synced_at then [ "Đã đồng bộ #{time_ago_in_words(feed.last_synced_at)} trước", "badge-success" ]
      else [ "Chưa đồng bộ", "badge-ghost" ]
      end
    tag.span(label, class: "badge badge-soft badge-sm #{color}")
  end

  # What the owner should do, instead of the raw error (admins also see that in Đồng bộ).
  def sync_error_message(error)
    case error.to_s
    when /HTTP (401|403|404|410)\b/ then "Link iCal không còn dùng được. Lấy link mới trên Airbnb / Booking.com rồi thêm lại kênh."
    when /not an iCalendar|larger than|public host|redirects/ then "Link này không đọc được thành lịch iCal (.ics). Kiểm tra lại link."
    else "Không tải được lịch lúc này. hueni tự thử lại mỗi giờ."
    end
  end
end
