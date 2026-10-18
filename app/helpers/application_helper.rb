module ApplicationHelper
  # Single source for the admin dock (phone) and sidebar (desktop). path: nil = page not built yet.
  def admin_menu_items
    items = [
      { label: "Tổng quan", icon: "home", path: admin_root_path, active: current_page?(admin_root_path) },
      { label: "Lịch phòng", icon: "calendar", path: admin_calendar_path, active: controller_name.in?(%w[calendars bookings]) },
      { label: "Kênh OTA", icon: "refresh", path: admin_calendar_feeds_path, active: controller_name == "calendar_feeds" }
    ]
    if Current.user&.place_memberships&.exists?(role: "owner")
      items << { label: "Báo cáo", icon: "chart", path: admin_report_path, active: controller_name == "reports" }
    end
    if Current.user&.admin?
      pending = RegistrationRequest.pending.count
      items << { label: pending.positive? ? "Người dùng (#{pending})" : "Người dùng", icon: "users", path: admin_users_path,
                 active: controller_name.in?(%w[users registration_requests]) }
      items << { label: "Đồng bộ", icon: "activity", path: admin_sync_runs_path, active: controller_name == "sync_runs" }
    end
    items
  end

  # "Chủ" / "Nhân viên" at this homestay.
  def place_role_badge(place)
    role = Current.user.role_at(place) or return
    tag.span(PlaceMembership::ROLE_LABELS.fetch(role), class: "badge badge-soft badge-sm #{role == "owner" ? "badge-primary" : "badge-info"}")
  end

  # Owners and staff can only log in once Zalo is linked (#97); admins also have a password.
  def zalo_badge(user)
    if user.zalo_id then tag.span("Zalo", class: "badge badge-soft badge-sm badge-success")
    elsif !user.admin? then tag.span("Chưa liên kết Zalo", class: "badge badge-soft badge-sm badge-warning")
    end
  end

  # Error shown under its field. The field points at it (and at its hint) with field_aria.
  def field_error(model, attribute)
    return unless model.errors.include?(attribute)
    tag.p model.errors.full_messages_for(attribute).to_sentence, id: "#{attribute}_error", class: "text-sm text-error mt-1"
  end

  def field_aria(model, attribute, hint: nil)
    invalid = model.errors.include?(attribute)
    { invalid: (true if invalid), describedby: [ hint, ("#{attribute}_error" if invalid) ].compact.join(" ").presence }
  end

  # "0912345678" → "0912 345 678"
  def phone(number)
    number.to_s.sub(/\A(\d{4})(\d{3})(\d{3})\z/, '\1 \2 \3')
  end
end
