require "test_helper"

class Admin::BookingsControllerTest < ActionDispatch::IntegrationTest
  def log_in(user)
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end

  setup do
    log_in users(:owner)
    travel_to Time.zone.local(2026, 10, 1, 12)
    @other_room = Room.create!(place: places(:hiuhill), name: "Đồi", max_guests: 2)
  end

  test "new form is prefilled from the tapped cell" do
    get new_admin_place_booking_path("tomo-homestay", room_id: rooms(:garden).id, start_date: "2026-10-05")
    assert_response :success
    assert_select "select[name='booking[room_id]'] option[selected][value=?]", rooms(:garden).id.to_s
    assert_select "input[name='booking[start_date]'][value='2026-10-05']"
    assert_select "input[name='booking[end_date]'][value='2026-10-06']"
  end

  test "creates a manual hold on the picked room, ignoring source" do
    assert_difference -> { rooms(:garden).bookings.count }, 1 do
      post admin_place_bookings_path("tomo-homestay"), params: { booking: {
        room_id: rooms(:garden).id, start_date: "2026-10-05", end_date: "2026-10-07", status: "hold",
        guest_name: "Chị Mai", guest_phone: "0905 123 456", note: "Đến muộn", source: "ical" } }
    end
    booking = Booking.last
    assert_equal [ "hold", "manual", "Chị Mai" ], [ booking.status, booking.source, booking.guest_name ]
    assert_redirected_to admin_place_calendar_path("tomo-homestay")
  end

  test "overlapping booking is rejected" do
    assert_no_difference -> { Booking.count } do
      post admin_place_bookings_path("tomo-homestay"), params: { booking: {
        room_id: rooms(:limdim).id, start_date: "2026-10-02", end_date: "2026-10-04", status: "hold" } }
    end
    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /Phòng đã có người đặt/
  end

  test "cannot book another owner's room or homestay" do
    assert_no_difference -> { Booking.count } do
      post admin_place_bookings_path("tomo-homestay"), params: { booking: { room_id: @other_room.id, start_date: "2026-10-05", end_date: "2026-10-06" } }
      assert_response :not_found
      post admin_place_bookings_path("hiuhill-homestay"), params: { booking: { room_id: @other_room.id, start_date: "2026-10-05", end_date: "2026-10-06" } }
      assert_response :not_found
    end
    get new_admin_place_booking_path("hiuhill-homestay")
    assert_response :not_found
  end

  test "edits a manual booking: confirm a hold, then cancel it" do
    booking = rooms(:garden).bookings.create!(start_date: "2026-10-05", end_date: "2026-10-06", status: "hold", guest_phone: "0905123456")
    get edit_admin_booking_path(booking)
    assert_response :success
    assert_select "a[href='tel:0905123456']"

    patch admin_booking_path(booking), params: { booking: { status: "confirmed" } }
    assert booking.reload.confirmed?
    assert_redirected_to admin_place_calendar_path("tomo-homestay")

    patch admin_booking_path(booking), params: { booking: { status: "cancelled" } }
    assert booking.reload.cancelled?
  end

  test "iCal and other owners' bookings cannot be edited" do
    ical = Booking.create!(room: rooms(:limdim), start_date: "2026-10-05", end_date: "2026-10-07", source: "ical",
      calendar_feed: calendar_feeds(:limdim_airbnb), uid: "a")
    other = @other_room.bookings.create!(start_date: "2026-10-05", end_date: "2026-10-06")

    [ ical, other ].each do |booking|
      get edit_admin_booking_path(booking)
      assert_response :not_found
      patch admin_booking_path(booking), params: { booking: { status: "cancelled" } }
      assert_response :not_found
      assert_not booking.reload.cancelled?
    end
  end
end
