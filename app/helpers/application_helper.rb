module ApplicationHelper
  # Single source for the admin dock (phone) and sidebar (desktop). path: nil = page not built yet.
  def admin_menu_items
    items = [
      { label: "Tổng quan", icon: "home", path: admin_root_path },
      { label: "Lịch phòng", icon: "calendar", path: nil },
      { label: "Kênh OTA", icon: "refresh", path: nil }
    ]
    items << { label: "Người dùng", icon: "users", path: nil } if Current.user&.admin?
    items
  end
end
