module Admin::ReportsHelper
  # 0.527 → "53%"; nil → "—"
  def percent(value) = value ? "#{(value * 100).round}%" : "—"

  # "1–19/10" for a month in progress, "28/9–4/10" for 7 ngày, else "tháng 10".
  def report_period(report)
    return "tháng #{report.month.month}" if report.month? && !report.partial?
    "#{report.first.strftime(report.first.month == report.last.month ? "%-d" : "%-d/%-m")}–#{report.last.strftime("%-d/%-m")}"
  end

  # "tăng 6%" / "giảm 0,5 đêm" against the previous period, as a soft badge: green when good, red when bad.
  # kind: :points (ratios, difference in % points), :percent (relative change), :nights (difference, one decimal).
  # Nothing when either side is unknown, or both are zero.
  def report_delta(current, previous, kind:, higher_is_better: true)
    return if current.nil? || previous.nil? || (current.zero? && previous.zero?) || (kind == :percent && previous.zero?)
    change = case kind
    when :points then (current - previous) * 100
    when :percent then (current - previous) * 100.0 / previous
    when :nights then current - previous
    end
    return tag.span("bằng", class: "badge badge-soft badge-sm") if change.round(1).zero?
    amount = number_with_precision(change.abs, precision: kind == :nights ? 1 : 0, strip_insignificant_zeros: true, separator: ",")
    text = "#{change.positive? ? "tăng" : "giảm"} #{amount}#{kind == :nights ? " đêm" : "%"}"
    tag.span(text, class: "badge badge-soft badge-sm #{(change.positive? == higher_is_better) ? "badge-success" : "badge-error"}")
  end
end
