module Admin::RoomsHelper
  def vnd(amount)
    number_to_currency(amount, unit: "₫", format: "%n %u", precision: 0, delimiter: ".") if amount
  end

  def room_status_badge(room, status)
    label, color =
      if !room.active? then [ "Đã tắt", "badge-ghost" ]
      elsif status == "confirmed" then [ "Đang có khách", "badge-info" ]
      elsif status == "hold" then [ "Giữ chỗ", "badge-warning" ]
      else [ "Trống", "badge-success" ]
      end
    tag.span(label, class: "badge badge-soft #{color}")
  end
end
