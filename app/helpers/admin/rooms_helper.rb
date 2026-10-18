module Admin::RoomsHelper
  def vnd(amount)
    number_to_currency(amount, unit: "₫", format: "%n %u", precision: 0, delimiter: ".") if amount
  end

  # "Phòng 101" for "101", but not "Phòng Phòng gia đình" when the owner already wrote it.
  def room_title(name) = name.to_s.match?(/\Aphòng\b/i) ? name : "Phòng #{name}"

  def vacancy_badge(left, active_count)
    label, color =
      if active_count.to_i.zero? then [ "Chưa có phòng", "badge-ghost" ]
      elsif left.to_i.positive? then [ "Còn #{left}/#{active_count} phòng hôm nay", "badge-success" ]
      else [ "Hết phòng hôm nay", "badge-neutral" ]
      end
    tag.span(label, class: "badge badge-soft #{color}")
  end
end
