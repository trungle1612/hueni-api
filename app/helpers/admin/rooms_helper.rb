module Admin::RoomsHelper
  def vnd(amount)
    number_to_currency(amount, unit: "₫", format: "%n %u", precision: 0, delimiter: ".") if amount
  end

  # A VND text field; on error it shows what the owner typed, not the half-parsed number.
  def price_field(form, attribute, hint: nil, placeholder: nil, autofocus: false)
    model = form.object
    value = model.errors.include?(attribute) ? model.public_send(:"#{attribute}_before_type_cast") : model.public_send(attribute)&.then { number_with_delimiter(it, delimiter: ".") }
    form.text_field attribute, inputmode: "numeric", value:, placeholder:, autofocus:,
      class: class_names("input input-lg w-full", "input-error": model.errors.include?(attribute)), aria: field_aria(model, attribute, hint:)
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
