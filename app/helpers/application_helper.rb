module ApplicationHelper
  # Single source for the admin dock (phone) and sidebar (desktop). path: nil = page not built yet.
  def admin_menu_items
    items = [
      { label: "Tổng quan", icon: "home", path: admin_root_path, active: current_page?(admin_root_path) },
      { label: "Lịch phòng", icon: "calendar", path: admin_calendar_path, active: controller_name.in?(%w[calendars bookings]) },
      { label: "Kênh OTA", icon: "refresh", path: admin_calendar_feeds_path, active: controller_name == "calendar_feeds" }
    ]
    items << { label: "Người dùng", icon: "users", path: admin_users_path, active: controller_name == "users" } if Current.user&.admin?
    items
  end

  # "0912345678" → "0912 345 678"
  def phone(number)
    number.to_s.sub(/\A(\d{4})(\d{3})(\d{3})\z/, '\1 \2 \3')
  end
end
