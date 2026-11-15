module Admin::ActivityHelper
  # Đồng bộ (sync runs): kind => [icon, round badge classes]. Full class names so Tailwind picks them up.
  ACTIVITY_KINDS = {
    error: [ "alert", "bg-error/15 text-error" ],
    ok: [ "check", "bg-success/15 text-success" ]
  }.freeze

  def activity_day(date)
    if date == Date.current then "Hôm nay"
    elsif date == Date.yesterday then "Hôm qua"
    else l(date, format: "%A %d/%m").upcase_first
    end
  end

  def activity_icon(kind, size: "size-9")
    icon, classes = ACTIVITY_KINDS.fetch(kind)
    tag.div(render("shared/icon", name: icon), class: "#{size} shrink-0 rounded-full flex items-center justify-center #{classes}")
  end
end
