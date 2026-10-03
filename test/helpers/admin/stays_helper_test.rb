require "test_helper"

class Admin::StaysHelperTest < ActionView::TestCase
  include Admin::CalendarsHelper

  setup { travel_to Time.zone.local(2026, 10, 2, 9) }

  test "late and overdue badges count days; only overdue is red" do
    booking = bookings(:limdim_confirmed) # 1/10–3/10, not checked in
    assert_dom_equal %(<span class="badge badge-soft badge-sm badge-warning">Trễ 1 ngày</span>), stay_badges(booking)

    booking.update_columns(checked_in_at: 1.day.ago)
    assert stay_badges(booking).blank?
    travel_to(Time.zone.local(2026, 10, 5, 9)) do
      assert_dom_equal %(<span class="badge badge-soft badge-sm badge-error">Quá hạn 2 ngày</span>), stay_badges(booking)
    end
  end

  test "check-in and check-out buttons ask for confirmation" do
    booking = bookings(:limdim_confirmed)
    assert_includes check_in_button(booking), %(data-turbo-confirm="Anh Minh nhận phòng Limdim?")
    assert_includes check_out_button(booking, size: "btn-sm"), %(data-turbo-confirm="Anh Minh trả phòng Limdim?")
    assert_includes check_out_button(booking, size: "btn-sm"), %(class="btn btn-sm")
  end

  test "call link only with a phone number" do
    assert_nil call_link(bookings(:limdim_confirmed))
    bookings(:limdim_confirmed).guest_phone = "0905 123 456"
    assert_includes call_link(bookings(:limdim_confirmed)), %(href="tel:0905123456")
  end

  test "room state label and colours" do
    day = RoomDay.for([ rooms(:limdim) ]).first
    assert_equal "Chờ khách", room_state_label(day)
    assert_includes room_tile_class(day), "bg-primary/15"
    assert_equal "01/10–03/10", stay_dates(day.booking)
  end

  test "no-show button asks first and cancels" do
    button = no_show_button(bookings(:limdim_confirmed), size: "btn-sm")
    assert_includes button, %(action="#{no_show_admin_booking_path(bookings(:limdim_confirmed))}")
    assert_includes button, %(data-turbo-confirm="Anh Minh không đến? Đặt phòng sẽ bị huỷ, phòng trống lại.")
    assert_includes button, "Không đến"
  end
end
