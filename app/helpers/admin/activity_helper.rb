module Admin::ActivityHelper
  # kind => [icon, round badge classes]. Full class names so Tailwind picks them up.
  ACTIVITY_KINDS = {
    check_in: [ "key", "bg-info/15 text-info" ],
    check_out: [ "log-out", "bg-secondary/15 text-secondary" ],
    clean: [ "sparkles", "bg-success/15 text-success" ],
    booking: [ "calendar", "bg-primary/15 text-primary" ],
    cancel: [ "x", "bg-base-300 text-base-content/70" ],
    edit: [ "pencil", "bg-base-300 text-base-content/70" ],
    sync: [ "refresh", "bg-accent/15 text-accent" ],
    room: [ "home", "bg-warning/15 text-warning" ],
    feed: [ "link", "bg-accent/15 text-accent" ],
    error: [ "alert", "bg-error/15 text-error" ],
    ok: [ "check", "bg-success/15 text-success" ],
    stay: [ "users", "bg-accent/15 text-accent" ],
    hold: [ "calendar", "bg-warning/15 text-warning" ]
  }.freeze

  # whodunnit => who: a user's name, an OTA ("airbnb" → "Airbnb"), or "Hệ thống" (console, seeds, unknown).
  def activity_names(versions) = Activity.actors(versions)

  def activity_room_names(versions) = Activity.room_names(versions)

  def activity_day(date)
    if date == Date.current then "Hôm nay"
    elsif date == Date.yesterday then "Hôm qua"
    else l(date, format: "%A %d/%m").upcase_first
    end
  end

  # { kind:, action:, detail: } for one change, e.g. { kind: :check_in, action: "Nhận phòng", detail: "Chị Mai" }.
  def activity_entry(version) = Activity.entry(version)

  def activity_icon(kind, size: "size-9")
    icon, classes = ACTIVITY_KINDS.fetch(kind)
    tag.div(render("shared/icon", name: icon), class: "#{size} shrink-0 rounded-full flex items-center justify-center #{classes}")
  end
end
