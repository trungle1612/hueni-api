module PmsHelper
  # "T4 21/10/2026", as in the design's top bar.
  def pms_day(date) = "#{%w[CN T2 T3 T4 T5 T6 T7][date.wday]} #{date.strftime("%d/%m/%Y")}"

  # "600.000đ", as in the design.
  def pms_money(amount) = "#{number_with_delimiter(amount, delimiter: ".")}đ"

  # A form field the model refused: red input, the message under it (aria via ApplicationHelper#field_aria).
  def pms_input_class(model, attribute) = class_names("pms-input", "pms-input-error": model.errors.include?(attribute))

  def pms_field_error(model, attribute)
    return unless model.errors.include?(attribute)
    tag.p model.errors.full_messages_for(attribute).to_sentence, id: "#{attribute}_error", class: "text-[13px] font-semibold text-pms-danger"
  end

  # "T4 21/10", as in Chi tiết đặt phòng.
  def pms_short_day(date) = "#{%w[CN T2 T3 T4 T5 T6 T7][date.wday]} #{date.strftime("%d/%m")}"

  # Chi tiết đặt phòng's chip: [tone, chip, note] as in the design.
  def pms_booking_state(booking)
    if booking.cancelled? then [ :danger, "Đã huỷ", booking.cancel_reason || "Phòng #{booking.room.name} đã trống lại" ]
    elsif booking.checked_out_at then [ :out, "Đã trả phòng", "Trả lúc #{booking.checked_out_at.strftime("%H:%M %d/%m")}" ]
    elsif booking.overdue? then [ :warn, "Quá hạn trả phòng", "Trả phòng #{pms_short_day(booking.end_date)}" ]
    elsif booking.checked_in_at then [ :in, "Đang ở", "Trả phòng #{pms_short_day(booking.end_date)}" ]
    elsif booking.start_date <= Booking.arrival_date then [ :ok, "Sắp đến", booking.start_date == Date.current ? "Đến hôm nay" : "Trễ từ #{pms_short_day(booking.start_date)}" ]
    else [ :ok, "Sắp đến", "Đến #{pms_short_day(booking.start_date)}" ]
    end
  end

  # "22 – 25/10", or "30/10 – 03/11" across months.
  def pms_range(from, to)
    "#{from.strftime(from.month == to.month ? "%d" : "%d/%m")} – #{to.strftime("%d/%m")}"
  end

  # Lịch phòng bar: [tone, status] as in the design. Tones: in / ok / warn / out (dashed) / maint.
  def pms_bar_state(booking)
    if booking.overdue? then [ :out, "Quá hạn trả phòng" ]
    elsif booking.departing_today? then [ :out, "Trả hôm nay" ]
    elsif booking.checked_in_at && !booking.checked_out_at then [ :in, "Đang ở" ]
    elsif booking.checked_out_at then [ :ok, "Đã trả phòng" ]
    elsif booking.awaiting_deposit? then [ :warn, "Chưa cọc" ]
    elsif booking.ical? || booking.due&.zero? then [ :ok, "Đã thanh toán" ]
    else [ :ok, "Đã cọc" ]
    end
  end

  # Grid placement of a Lịch phòng bar from `from` to the morning of `to` within days (a 7-day range): a stay starts
  # mid-cell (afternoon check-in) and ends mid-cell (morning check-out); cont = it began before the week or fills the day.
  def pms_bar_style(days, from, to, cont: false)
    start = [ (from - days.begin).to_i, 0 ].max
    finish = (to - days.begin).to_i
    cont ||= from < days.begin
    half = finish < days.count
    cover = half ? finish - start + 1 : days.count - start
    "grid-column: #{start + 2} / span #{cover}; margin-left: #{cont ? "1px" : "#{50.0 / cover}%"}; margin-right: #{half ? "#{50.0 / cover}%" : "1px"}"
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
