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

  def vacancy_badge(left, active_count)
    label, color =
      if active_count.to_i.zero? then [ "Chưa có phòng", "badge-ghost" ]
      elsif left.to_i.positive? then [ "Còn #{left}/#{active_count} phòng hôm nay", "badge-success" ]
      else [ "Hết phòng hôm nay", "badge-neutral" ]
      end
    tag.span(label, class: "badge badge-soft #{color}")
  end
end
