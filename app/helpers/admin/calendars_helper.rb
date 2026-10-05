module Admin::CalendarsHelper
  # [[booking, lane], ...]: each booking goes in the first lane free by its start date, so overlaps stack.
  def timeline_lanes(bookings)
    lane_ends = []
    bookings.sort_by(&:start_date).map do |booking|
      lane = lane_ends.index { it <= booking.start_date } || lane_ends.size
      lane_ends[lane] = booking.end_date
      [ booking, lane ]
    end
  end

  def booking_bar_label(booking) = "#{"✓ " if booking.checked_out_at}#{"⚠ " if booking.removed_from_feed_at}#{booking_label(booking)}"

  def booking_label(booking) = booking.label

  def booking_bar_class(booking)
    if booking.checked_out_at then "bg-primary/15 text-primary/80"
    elsif booking.ical? then "bg-base-300 text-base-content border border-base-content/20"
    elsif booking.hold? then "bg-warning/25 text-warning-content border border-dashed border-warning"
    else "bg-primary text-primary-content"
    end
  end
end
