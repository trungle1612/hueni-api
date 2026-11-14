require "test_helper"

# Hôm nay in the PWA (#229): Today's lists for the current homestay, Nhận / Trả phòng, Hoàn tác.
class Pms::TodayTest < ActionDispatch::IntegrationTest
  setup { travel_to Time.zone.local(2026, 10, 2, 9) }

  test "lists arrivals and departures like /admin, with counts and Cần xử lý" do
    # limdim_confirmed (1/10–3/10, Anh Minh) is not checked in: a late arrival into a dirty room.
    leaving = rooms(:garden).bookings.create!(start_date: "2026-09-30", end_date: "2026-10-02", guest_name: "Chị Mai", price: 300_000)
    leaving.update_columns(checked_in_at: 2.days.ago, declared_at: 2.days.ago)
    rooms(:limdim).dirty!
    log_in users(:owner)

    get pms_today_path
    assert_response :success
    assert_select "#stats", text: /1\s*Chờ đến.*1\s*Chờ đi.*0\/2\s*Đang ở.*1\s*Cần dọn/m
    assert_select "header", text: /T6 02\/10\/2026 · tomo homestay/
    assert_select "header a[href='#{admin_search_path}'][aria-label='Tìm đặt phòng']"
    assert_select "header a[href='#{new_admin_place_booking_path("tomo-homestay")}']", "+ Đặt phòng"
    assert_select "#stats a[href='#{admin_place_path("tomo-homestay")}']", text: /1\s*Cần dọn/
    assert_select "#issues a.pms-notice", text: /Khách đến, phòng chưa dọn · Anh Minh · Phòng Limdim\s*Xem/
    assert_select "#nhan-phong", text: /Nhận phòng · 1 chờ \/ 1/
    assert_select "#tra-phong", text: /Trả phòng · 1 chờ \/ 1/
    assert_select "#today_booking_#{bookings(:limdim_confirmed).id}", text: /Anh Minh.*2 đêm.*trễ 1 ngày/m
    assert_select "#today_booking_#{leaving.id}", text: /Chị Mai.*Còn thu 600.000đ/m
    # Money due, a dirty room or no head count: a bottom sheet first.
    assert_select "#sheet_booking_#{leaving.id}[popover] button[name=collect][value='1']", "Đã thu 600.000đ, trả phòng"
    assert_select "#sheet_booking_#{leaving.id} button", "Trả phòng, ghi nợ"
    assert_select "#sheet_booking_#{bookings(:limdim_confirmed).id}", text: /Phòng Limdim chưa dọn xong/
    assert_select "#sheet_booking_#{bookings(:limdim_confirmed).id} input[name=guests][required][max='4']"
  end

  test "Ngày mai: the same lists for tomorrow, nothing to press" do
    rooms(:garden).bookings.create!(start_date: "2026-10-03", end_date: "2026-10-05", guest_name: "Cô Ba")
    log_in users(:owner)
    get pms_today_path(day: "mai")
    assert_select "header", text: /Xem trước T7 03\/10\/2026/
    assert_select "#stats", text: /1\s*Sẽ đến.*1\s*Sẽ đi/m
    assert_select "main", text: /Cô Ba/
    assert_select "main form", count: 0
    assert_select "#issues", count: 0
  end

  test "before 06:00 a late arrival still counts for the previous day" do
    travel_to Time.utc(2026, 10, 2, 17, 30) # 00:30 on 3/10, Anh Minh: 1/10–3/10
    log_in users(:owner)
    get pms_today_path
    assert_select "#today_booking_#{bookings(:limdim_confirmed).id}"
    travel_to Time.zone.local(2026, 10, 3, Booking::LATE_ARRIVAL_UNTIL)
    get pms_today_path
    assert_select "#today_booking_#{bookings(:limdim_confirmed).id}", count: 0
  end

  test "check-in collects what is due, then the toast offers Hoàn tác to owners" do
    booking = bookings(:limdim_confirmed)
    booking.update!(price: 200_000)
    log_in users(:owner)

    post pms_stay_check_in_path(booking), params: { guests: 2, collect: "1" }
    assert_redirected_to pms_today_path
    assert booking.reload.checked_in_at
    assert_equal 400_000, booking.paid
    follow_redirect!
    assert_select ".pms-toast", text: /Đã nhận phòng Limdim · đã thu 400.000đ/
    assert_select ".pms-toast form[action='#{pms_stay_undo_check_in_path(booking)}']"
    assert_select "#nhan-phong", text: /Nhận phòng · 0 chờ \/ 1/
    assert_select "#today_booking_#{booking.id}", text: /Anh Minh.*Đã nhận/m

    post pms_stay_undo_check_in_path(booking)
    assert_nil booking.reload.checked_in_at
  end

  test "check-in refused while another guest is in the room shows the model's message" do
    rooms(:limdim).bookings.create!(start_date: "2026-09-30", end_date: "2026-10-01", guest_name: "Anh Tú")
      .update_columns(checked_in_at: 3.days.ago)
    log_in users(:owner)
    post pms_stay_check_in_path(bookings(:limdim_confirmed)), params: { guests: 2 }
    assert_nil bookings(:limdim_confirmed).reload.checked_in_at
    follow_redirect!
    assert_select "[role=alert]", text: "Phòng đang có khách chưa trả phòng"
  end

  test "check-out keeps the row as Đã trả" do
    booking = bookings(:limdim_confirmed)
    booking.check_in(guests: 2)
    log_in users(:owner)
    post pms_stay_check_out_path(booking)
    assert booking.reload.checked_out_at
    assert rooms(:limdim).reload.dirty?
    follow_redirect!
    assert_select ".pms-toast", text: /Đã trả phòng Limdim/
    assert_select "#tra-phong", text: "Trả phòng · 0 chờ / 1"
    assert_select "section[aria-labelledby=tra-phong]", text: /Anh Minh.*Đã trả/m
  end

  test "staff check in, but get no Hoàn tác (403)" do
    places(:tomo).place_memberships.create!(user: users(:admin), role: "staff")
    booking = bookings(:limdim_confirmed)
    log_in users(:admin)

    post pms_stay_check_in_path(booking), params: { guests: 2 }
    assert booking.reload.checked_in_at
    follow_redirect!
    assert_select ".pms-toast", text: /Đã nhận phòng Limdim/
    assert_select ".pms-toast form", count: 0

    post pms_stay_undo_check_in_path(booking)
    assert_response :forbidden
    assert_select "h2", "Bạn chưa có quyền"
    assert booking.reload.checked_in_at
  end

  test "another owner's booking is not found" do
    other = Room.create!(place: places(:hiuhill), name: "Đồi", max_guests: 2)
    stay = other.bookings.create!(start_date: "2026-10-02", end_date: "2026-10-03", guest_name: "Khách khác", guests: 1)
    log_in users(:owner)

    post pms_stay_check_in_path(stay)
    assert_response :not_found
    post pms_stay_undo_check_out_path(stay)
    assert_response :not_found
    assert_nil stay.reload.checked_in_at
  end
end
