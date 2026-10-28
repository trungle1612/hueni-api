module Admin::CalendarFeedsHelper
  # 15.5 → "15,5", 15.0 → "15"; nil stays blank.
  def commission(value) = value && number_with_precision(value, precision: 1, strip_insignificant_zeros: true, separator: ",")

  def feed_status_badge(feed)
    label, color =
      if feed.last_error then [ "Lỗi #{time_ago_in_words(feed.last_error_at)} trước", "badge-error" ]
      elsif feed.last_synced_at then [ "Đã đồng bộ #{time_ago_in_words(feed.last_synced_at)} trước", "badge-success" ]
      else [ "Chưa đồng bộ", "badge-ghost" ]
      end
    tag.span(label, class: "badge badge-soft badge-sm #{color}")
  end

  # What the owner should do, instead of the raw error (admins also see that in Đồng bộ).
  def sync_error_message(error) = CalendarFeed::ERROR_MESSAGES.fetch(CalendarFeed.error_kind(error))
end
