require "test_helper"

# Chi tiết đặt phòng + Sửa đặt phòng in the PWA (#231).
class Pms::BookingTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 10, 1, 14)
    @booking = bookings(:limdim_confirmed) # Limdim 1/10–3/10, Anh Minh
    @booking.update!(price: 200_000, guest_phone: "0905 123 456", note: "Đi xe máy")
    @booking.payments.create!(amount: 100_000, payment_method: "cash", note: "Cọc")
  end

  def staff!
    places(:tomo).place_memberships.create!(user: users(:admin), role: "staff")
    log_in users(:admin)
  end

  test "owner sees guest, stay, money and history, with Nhận phòng in the action bar" do
    log_in users(:owner)
    get pms_booking_path(@booking)
    assert_response :success
    assert_select "header h1", "Anh Minh"
    assert_select "header a[href=?]", edit_pms_booking_path(@booking), text: "Sửa"
    assert_select "#state", text: /Sắp đến\s*Đến hôm nay/
    assert_select "a[href='tel:0905123456']", "Gọi"
    assert_select "section[aria-labelledby=h-stay]", text: /T5 01\/10.*T7 03\/10.*Limdim · 2 đêm/m
    assert_select "#thanh-toan", text: /2 đêm × 200.000đ\s*400.000đ.*Cọc · tiền mặt · 01\/10\s*−100.000đ/m
    assert_select "#due", text: /Còn phải thu\s*300.000đ/
    assert_select "#history", text: /Hệ thống · Thu tiền · 100.000 ₫/
    assert_select "nav[aria-label='Điều hướng chính']", 0
    # Money due: Nhận phòng opens the sheet that collects it.
    assert_select "button[popovertarget=sheet_booking_#{@booking.id}]", "Nhận phòng"
    assert_select "#sheet_booking_#{@booking.id} button[name=collect]", "Đã thu 300.000đ, nhận phòng"
    assert_select "#cancel[popover]"
  end

  test "staff see the total but not the nightly price or the history, and cannot refund" do
    staff!
    get pms_booking_path(@booking)
    assert_select "#thanh-toan", text: /Tiền phòng\s*400.000đ/
    assert_select "#thanh-toan", text: /200.000đ/, count: 0
    assert_select "#history", 0
    assert_select "#refund", text: /Giữ lại tiền cọc.*Chỉ chủ cơ sở hoàn cọc được/m
    assert_select "#refund input[value=cash]", 0

    get edit_pms_booking_path(@booking)
    assert_select "input[name='booking[price]']", 0
    patch pms_booking_path(@booking), params: { booking: { price: 1, guests: 2 } }
    assert_equal [ 200_000, 2 ], @booking.reload.values_at(:price, :guests)

    patch pms_booking_path(@booking), params: { booking: { status: "cancelled", cancel_reason: "Khách huỷ" }, refund_method: "cash" }
    assert @booking.reload.cancelled?
    assert_equal 100_000, @booking.paid
  end

  test "check-in from the detail page comes back to it, with Hoàn tác" do
    log_in users(:owner)
    post pms_stay_check_in_path(@booking), params: { guests: 2 }, headers: { "Referer" => pms_booking_url(@booking) }
    assert_redirected_to pms_booking_url(@booking)
    follow_redirect!
    assert_select ".pms-toast", text: /Đã nhận phòng Limdim · ghi nợ 300.000đ/
    assert_select ".pms-toast form[action=?]", pms_stay_undo_check_in_path(@booking)
    assert_select "#state", text: /Đang ở/
    assert_select "button[popovertarget=sheet_booking_#{@booking.id}]", "Trả phòng"
    assert_select "#cancel", 0
  end

  test "Nhận phòng sớm when the room is free from today" do
    later = rooms(:garden).bookings.create!(start_date: "2026-10-04", end_date: "2026-10-06", guest_name: "Cô Ba", guests: 2)
    log_in users(:owner)
    get pms_booking_path(later)
    assert_select "form[action=?] button", pms_stay_check_in_path(later), text: "Nhận phòng sớm"
  end

  test "Thu tiền: the model refuses more than is due" do
    staff!
    post pms_booking_payments_path(@booking), params: { payment: { amount: "400k", payment_method: "bank" } }
    assert_redirected_to pms_booking_path(@booking)
    follow_redirect!
    assert_select "[role=alert]", text: /không được lớn hơn số còn phải thu \(300.000 ₫\)/
    assert_equal 100_000, @booking.reload.paid

    post pms_booking_payments_path(@booking), params: { payment: { amount: "300.000", payment_method: "bank", kind: "refund" } }
    follow_redirect!
    assert_select ".pms-toast", text: "Đã ghi nhận 300.000đ · Chuyển khoản"
    assert_select "#due", text: /0đ · đã thu đủ/
    assert_select "button", text: "Ghi nhận thanh toán", count: 0
  end

  test "Dịch vụ: added from the catalog, removed by staff" do
    service = places(:tomo).services.create!(name: "Thuê xe máy", price: 120_000, unit: "ngày")
    staff!
    post pms_booking_charges_path(@booking), params: { service_id: service.id, quantity: 2 }
    follow_redirect!
    assert_select ".pms-toast", text: "Đã thêm Thuê xe máy × 2 ngày"
    charge = @booking.charges.reload.sole
    assert_select "##{ActionView::RecordIdentifier.dom_id(charge)}", text: /Thuê xe máy · 2 ngày × 120.000đ\s*240.000đ/
    assert_select "#due", text: /540.000đ/

    delete pms_booking_charge_path(@booking, charge)
    assert_empty @booking.charges.reload
  end

  test "Huỷ needs a reason, can refund for owners, stays visible and can be restored" do
    log_in users(:owner)
    patch pms_booking_path(@booking), params: { booking: { status: "cancelled" } }
    follow_redirect!
    assert_select "[role=alert]", text: /Lý do huỷ/
    assert @booking.reload.confirmed?

    patch pms_booking_path(@booking), params: { booking: { status: "cancelled", cancel_reason: "other", cancel_reason_other: "Đổi ý" }, refund_method: "bank" }
    follow_redirect!
    assert_select ".pms-toast", text: "Đã huỷ đặt phòng · đã hoàn 100.000đ"
    assert_select "#state", text: /Đã huỷ\s*Đổi ý/
    assert_select "#thanh-toan", text: /Hoàn cọc · chuyển khoản/
    assert_equal 0, @booking.reload.paid

    patch pms_booking_path(@booking), params: { booking: { status: "confirmed" } }
    follow_redirect!
    assert_select ".pms-toast", text: "Đã khôi phục đặt phòng"
    assert @booking.reload.confirmed?
  end

  test "Sửa: the live check and saving use the model's date rules" do
    rooms(:limdim).bookings.create!(start_date: "2026-10-04", end_date: "2026-10-06", guest_name: "Cô Ba")
    log_in users(:owner)

    get availability_pms_booking_path(@booking, start_date: "2026-10-01", end_date: "2026-10-05")
    assert_select "#dates_error", text: /Phòng khác còn trống: Garden/
    get availability_pms_booking_path(@booking, start_date: "2026-10-01", end_date: "2026-10-04")
    assert_select "turbo-frame#availability", text: /Không trùng lịch · 3 đêm/

    patch pms_booking_path(@booking), params: { booking: { end_date: "2026-10-05" } }
    assert_response :unprocessable_entity
    assert_select "#dates_error"
    assert_select "input[name='booking[end_date]'][aria-invalid=true]"

    patch pms_booking_path(@booking), params: { booking: { end_date: "2026-10-04", guest_name: "Anh Minh Trần", price: "250k" } }
    assert_redirected_to pms_booking_path(@booking)
    follow_redirect!
    assert_select ".pms-toast", text: "Đã lưu thay đổi"
    assert_select "#thanh-toan", text: /3 đêm × 250.000đ/
  end

  test "a checked-out stay is history: no Sửa, saving refused with the model's message" do
    @booking.check_in(guests: 2)
    @booking.check_out
    log_in users(:owner)
    get pms_booking_path(@booking)
    assert_select "#state", text: /Đã trả phòng/
    assert_select "header a", text: "Sửa", count: 0
    patch pms_booking_path(@booking), params: { booking: { guest_name: "X" } }
    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: "Khách đã trả phòng, không sửa được đặt phòng."
  end

  test "iCal bookings open read-only" do
    ical = Booking.create!(room: rooms(:garden), start_date: "2026-10-05", end_date: "2026-10-07", source: "ical",
      calendar_feed: calendar_feeds(:limdim_airbnb), uid: "x")
    log_in users(:owner)
    get pms_booking_path(ical)
    assert_response :success
    assert_select "#thanh-toan", text: /Khách thanh toán qua Airbnb/
    assert_select "header a", text: "Sửa", count: 0
    assert_select "#cancel, #pay", 0
    get edit_pms_booking_path(ical)
    assert_response :not_found
    post pms_booking_payments_path(ical), params: { payment: { amount: 1, payment_method: "cash" } }
    assert_response :not_found
  end

  test "another owner's booking is not found" do
    room = Room.create!(place: places(:hiuhill), name: "Đồi", max_guests: 2)
    stay = room.bookings.create!(start_date: "2026-10-02", end_date: "2026-10-03", guest_name: "Khách khác")
    service = places(:hiuhill).services.create!(name: "Nước", price: 10_000)
    log_in users(:owner)

    get pms_booking_path(stay)
    assert_response :not_found
    get edit_pms_booking_path(stay)
    assert_response :not_found
    patch pms_booking_path(stay), params: { booking: { guest_name: "X" } }
    assert_response :not_found
    post pms_booking_payments_path(stay), params: { payment: { amount: 1, payment_method: "cash" } }
    assert_response :not_found
    post pms_booking_charges_path(stay), params: { service_id: service.id }
    assert_response :not_found
    # Another homestay's service on our own booking.
    post pms_booking_charges_path(@booking), params: { service_id: service.id }
    assert_response :not_found
    assert_equal "Khách khác", stay.reload.guest_name
  end
end
