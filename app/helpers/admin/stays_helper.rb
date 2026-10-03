module Admin::StaysHelper
  # state => [label, badge colour, board tile fill]. Full class names so Tailwind picks them up.
  ROOM_STATES = {
    off: [ "Đã tắt", "badge-ghost", "bg-base-200 opacity-60" ],
    leaving: [ "Trả hôm nay", "badge-accent", "bg-accent/15" ],
    occupied: [ "Đang có khách", "badge-info", "bg-info/15" ],
    arriving: [ "Chờ khách", "badge-primary", "bg-primary/15" ],
    held: [ "Giữ chỗ", "badge-warning", "bg-warning/15" ],
    free: [ "Trống", "badge-success", "bg-success/15" ]
  }.freeze

  def room_state_label(day) = ROOM_STATES.fetch(day.state)[0]
  def room_state_badge(day) = tag.span(room_state_label(day), class: "badge badge-soft #{ROOM_STATES.fetch(day.state)[1]}")
  def room_tile_class(day) = ROOM_STATES.fetch(day.state)[2]

  def stay_dates(booking) = "#{booking.start_date.strftime("%d/%m")}–#{booking.end_date.strftime("%d/%m")}"

  def stay_badges(booking)
    today = Date.current
    badges = []
    badges << stay_badge("Trễ #{(today - booking.start_date).to_i} ngày", "badge-warning") if !booking.checked_in_at && booking.start_date < today
    badges << stay_badge("Quá hạn #{(today - booking.end_date).to_i} ngày", "badge-error") if booking.can_check_out? && booking.end_date < today
    safe_join(badges, " ")
  end

  # No undo exists, so both ask first.
  def check_in_button(booking, size: nil)
    button_to "Check-in", check_in_admin_booking_path(booking), class: [ "btn btn-primary", size ].compact.join(" "),
      form: { data: { turbo_confirm: "#{booking_label(booking)} nhận phòng #{booking.room.name}?" } }
  end

  def check_out_button(booking, size: nil)
    button_to "Check-out", check_out_admin_booking_path(booking), class: [ "btn", size ].compact.join(" "),
      form: { data: { turbo_confirm: "#{booking_label(booking)} trả phòng #{booking.room.name}?" } }
  end

  def no_show_button(booking, size: nil)
    button_to "Không đến", no_show_admin_booking_path(booking), class: [ "btn btn-ghost text-error", size ].compact.join(" "),
      form: { data: { turbo_confirm: "#{booking_label(booking)} không đến? Đặt phòng sẽ bị huỷ, phòng trống lại." } }
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
