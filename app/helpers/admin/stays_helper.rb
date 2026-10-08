module Admin::StaysHelper
  # state => [label, tile / band fill]. Full class names so Tailwind picks them up.
  ROOM_STATES = {
    off: [ "Đã tắt", "bg-base-200" ],
    leaving: [ "Trả hôm nay", "bg-accent/15" ],
    occupied: [ "Đang có khách", "bg-info/15" ],
    arriving: [ "Chờ khách", "bg-primary/15" ],
    held: [ "Giữ chỗ", "bg-warning/15" ],
    free: [ "Trống", "bg-success/15" ]
  }.freeze

  def room_state_label(day) = ROOM_STATES.fetch(day.state)[0]
  def room_tile_class(day) = ROOM_STATES.fetch(day.state)[1]

  def stay_dates(booking) = "#{booking.start_date.strftime("%d/%m")}–#{booking.end_date.strftime("%d/%m")}"

  def stay_badges(booking)
    today = Date.current
    badges = []
    late = (Booking.arrival_date - booking.start_date).to_i
    badges << stay_badge("Trễ #{late} ngày", "badge-warning") if !booking.checked_in_at && late.positive?
    badges << stay_badge("OTA đã huỷ", "badge-error") if booking.removed_from_feed_at
    badges << stay_badge("Chưa khai báo lưu trú", "badge-warning") if booking.needs_declaration?
    badges << stay_badge("Quá hạn #{(today - booking.end_date).to_i} ngày", "badge-error") if booking.overdue?
    safe_join(badges, " ")
  end

  # Only owners can undo (Hoàn tác), so both ask first. Check-in doesn't validate (it records a fact), so the
  # question carries what would have failed: an overlapping booking, too many guests.
  # Only an unchanged booking is checked: validating would wipe a failed edit form's errors.
  def check_in_button(booking, size: nil)
    label, confirm =
      if booking.early_check_in?
        [ "Nhận phòng sớm", "#{booking_label(booking)} nhận phòng sớm #{booking.room.name}? Ngày đến đổi #{booking.start_date.strftime("%d/%m")} → #{Date.current.strftime("%d/%m")}" ]
      else
        [ "Check-in", "#{booking_label(booking)} nhận phòng #{booking.room.name}?" ]
      end
    confirm += "\n⚠ #{booking.errors.full_messages.join(". ")}" if !booking.changed? && booking.errors.empty? && booking.invalid?
    return button_to(label, check_in_admin_booking_path(booking), class: [ "btn btn-primary", size ].compact.join(" "),
      form: { data: { turbo_confirm: confirm } }) if booking.guests

    form_with url: check_in_admin_booking_path(booking), class: "flex gap-1", data: { turbo_confirm: confirm } do |form|
      form.number_field(:guests, in: 1..booking.room.max_guests, required: true, placeholder: "Số khách",
        class: [ "input w-24", size&.sub("btn", "input") ].compact.join(" "), aria: { label: "Số khách" }) +
        form.button(label, class: [ "btn btn-primary", size ].compact.join(" "))
    end
  end

  def declare_button(booking, size: nil)
    button_to "Đã khai báo", declare_admin_booking_path(booking), class: [ "btn btn-outline", size ].compact.join(" ")
  end

  def check_out_button(booking, size: nil)
    button_to "Check-out", check_out_admin_booking_path(booking), class: [ "btn", size ].compact.join(" "),
      form: { data: { turbo_confirm: "#{booking_label(booking)} trả phòng #{booking.room.name}?" } }
  end

  def no_show_button(booking, size: nil)
    button_to "Không đến", no_show_admin_booking_path(booking), class: [ "btn btn-ghost text-error", size ].compact.join(" "),
      form: { data: { turbo_confirm: "#{booking_label(booking)} không đến? Đặt phòng sẽ bị huỷ, phòng trống lại." } }
  end

  # Hoàn tác check-in / check-out (owners, same day).
  def undo_button(booking, step, size: nil)
    path, question =
      if step == :check_in then [ undo_check_in_admin_booking_path(booking), "Hoàn tác nhận phòng của #{booking_label(booking)}? Khách quay lại Chờ khách." ]
      else [ undo_check_out_admin_booking_path(booking), "Hoàn tác trả phòng của #{booking_label(booking)}? Khách quay lại Đang ở." ]
      end
    button_to "Hoàn tác", path, class: [ "btn btn-ghost", size ].compact.join(" "), form: { data: { turbo_confirm: question } }
  end

  def clean_button(room, size: nil)
    button_to "Dọn xong", clean_admin_room_path(room), class: [ "btn btn-outline", size ].compact.join(" ")
  end

  def call_link(booking)
    return if booking.guest_phone.blank?
    link_to render("shared/icon", name: "phone"), "tel:#{booking.guest_phone.delete(" ")}",
      class: "btn btn-ghost btn-square", aria: { label: "Gọi #{booking.guest_phone}" }
  end

  private
    def stay_badge(text, colour) = tag.span(text, class: "badge badge-soft badge-sm #{colour}")
end
