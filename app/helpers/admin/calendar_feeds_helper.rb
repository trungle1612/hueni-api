module Admin::CalendarFeedsHelper
  def feed_status_badge(feed)
    label, color =
      if feed.last_error then [ "Lỗi #{time_ago_in_words(feed.last_error_at)} trước", "badge-error" ]
      elsif feed.last_synced_at then [ "Đã đồng bộ #{time_ago_in_words(feed.last_synced_at)} trước", "badge-success" ]
      else [ "Chưa đồng bộ", "badge-ghost" ]
      end
    tag.span(label, class: "badge badge-soft badge-sm #{color}")
  end
end
