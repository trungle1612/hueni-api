module Admin::ReportsHelper
  # 0.527 → "53%"; nil → "—"
  def percent(value) = value ? "#{(value * 100).round}%" : "—"

  # ▲ / ▼ against the previous month. kind: :points (ratios, difference in points), :percent (relative change),
  # :number (absolute difference, one decimal). Green when the change is good, red when bad; nothing when unknown.
  def report_delta(current, previous, kind:, higher_is_better: true)
    return if current.nil? || previous.nil? || (kind == :percent && previous.zero?)
    change = case kind
    when :points then (current - previous) * 100
    when :percent then (current - previous) * 100.0 / previous
    when :number then current - previous
    end
    return tag.span("= tháng trước", class: "opacity-60") if change.round(1).zero?
    text = "#{change.positive? ? "▲" : "▼"} #{number_with_precision(change.abs, precision: kind == :number ? 1 : 0, strip_insignificant_zeros: true, separator: ",")}"
    text += { points: " điểm", percent: "%", number: "" }.fetch(kind)
    tag.span(text, class: (change.positive? == higher_is_better) ? "text-success" : "text-error")
  end
end
