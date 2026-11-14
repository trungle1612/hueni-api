module PmsHelper
  # "T4 21/10/2026", as in the design's top bar.
  def pms_day(date) = "#{%w[CN T2 T3 T4 T5 T6 T7][date.wday]} #{date.strftime("%d/%m/%Y")}"

  # "600.000đ", as in the design.
  def pms_money(amount) = "#{number_with_delimiter(amount, delimiter: ".")}đ"

  # Until the PWA has Chi tiết đặt phòng (#231) and Lịch phòng (#230), rows open the /admin pages.
  def pms_booking_href(booking)
    booking.manual? ? edit_admin_booking_path(booking) : admin_place_calendar_path(booking.room.place.slug, from: booking.start_date.iso8601)
  end

  # Second line of a Hôm nay row: "2 đêm · 2 khách · Airbnb · chưa cọc".
  def pms_stay_meta(booking, departing: false)
    late = (Booking.arrival_date - booking.start_date).to_i
    [
      departing ? "Đến #{booking.start_date.strftime("%d/%m")}" : "#{(booking.end_date - booking.start_date).to_i} đêm",
      ("#{booking.guests} khách" if booking.guests),
      (booking.calendar_feed&.provider_label if booking.ical?),
      ("chưa cọc" if booking.awaiting_deposit?),
      ("trễ #{late} ngày" if !booking.checked_in_at && late.positive?),
      ("quá hạn #{(Date.current - booking.end_date).to_i} ngày" if booking.overdue?),
      ("OTA đã huỷ" if booking.removed_from_feed_at)
    ].compact.join(" · ")
  end
end
