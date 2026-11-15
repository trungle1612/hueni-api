require "test_helper"

# Đặt phòng mới in the PWA (#232).
class Pms::NewBookingTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 10, 1, 14)
    rooms(:limdim).update!(price: 300_000, weekend_price: 350_000) # Anh Minh 1/10–3/10
    rooms(:garden).update!(price: 250_000)
  end

  def form(**booking) = { booking: { start_date: "2026-10-01", end_date: "2026-10-03", guest_name: "Cô Ba", guest_phone: "0905 111 333", guests: 2, **booking } }

  test "the form offers free rooms only, busy ones disabled, prefilled from a Lịch phòng cell" do
    log_in users(:owner)
    get new_pms_booking_path
    assert_response :success
    assert_select "header h1", "Đặt phòng mới"
    assert_select "legend", text: "Phòng · 1 phòng trống 01 – 02/10"
    assert_select "input[name='booking[room_id]'][value='#{rooms(:limdim).id}'][disabled]"
    assert_select "input[name='booking[room_id]'][value='#{rooms(:garden).id}'][checked]"
    assert_select "#quote_footer", text: /250.000đ\s*1 đêm × 250.000đ · còn thu 250.000đ\s*Lưu đặt phòng/
    assert_select "#money_note", text: /Để trống: lấy giá phòng Garden 250.000đ/
    assert_select "nav[aria-label='Điều hướng chính']", 0

    get new_pms_booking_path(room_id: rooms(:limdim).id, start_date: "2026-10-03")
    assert_select "input[name='booking[room_id]'][value='#{rooms(:limdim).id}'][checked]"
    assert_select "input[name='booking[start_date]'][value='2026-10-03']"
    assert_select "input[name='booking[end_date]'][value='2026-10-04']"
  end

  test "the quote frame recomputes rooms, total and còn thu, and shows the model's deposit error" do
    log_in users(:owner)
    get rooms_pms_bookings_path, params: form(room_id: rooms(:limdim).id, price: "200k", deposit: "100.000")
    assert_select "turbo-frame#quote input[value='#{rooms(:garden).id}'][checked]"
    assert_select "turbo-stream[target=quote_footer] template", text: /400.000đ.*2 đêm × 200.000đ · còn thu 300.000đ/m

    get rooms_pms_bookings_path, params: form(room_id: rooms(:garden).id, deposit: "600k")
    assert_select "turbo-stream[target=money_note] template", text: /Đã cọc không được lớn hơn tiền phòng \(500.000 ₫\)/

    rooms(:garden).bookings.create!(start_date: "2026-10-04", end_date: "2026-10-05", guest_name: "Anh Tư")
    get rooms_pms_bookings_path, params: form(start_date: "2026-10-02", end_date: "2026-10-05")
    assert_select "turbo-frame#quote", text: /0 phòng trống.*Không còn phòng trống trong các ngày này/m
    assert_select "turbo-stream[target=quote_footer] button[disabled]", "Lưu đặt phòng"
  end

  test "Khách cũ by phone" do
    rooms(:garden).bookings.create!(start_date: "2026-09-10", end_date: "2026-09-12", guest_name: "Chị Hoa", guest_phone: "0905 111 333")
    log_in users(:owner)
    get guest_pms_bookings_path, params: { booking: { guest_phone: "+84905111333" } }
    assert_select "turbo-frame#returning", text: /Khách cũ: Chị Hoa · đã ở 1 lần/
    assert_select "button[data-pms-booking-name-param='Chị Hoa']", "Dùng thông tin"
    get guest_pms_bookings_path, params: { booking: { guest_phone: "0905" } }
    assert_select "turbo-frame#returning", text: ""
  end

  test "saving snapshots the room's prices, records the deposit, then Đã lưu" do
    log_in users(:owner)
    assert_difference -> { Booking.count } do
      post pms_bookings_path, params: form(room_id: rooms(:garden).id, deposit: "100k", deposit_method: "bank")
    end
    booking = Booking.last
    assert_redirected_to saved_pms_booking_path(booking)
    assert_equal [ 250_000, nil ], [ booking.price, booking.weekend_price ]
    assert_equal [ 100_000, "bank" ], booking.payments.sole.values_at(:amount, :payment_method)

    follow_redirect!
    assert_select "[role=status]", text: /Đã lưu đặt phòng DP-\d{4}/
    assert_select "#summary", text: /Cô Ba.*Phòng Garden.*01 – 03\/10 · 2 đêm.*500.000đ.*100.000đ.*Còn phải thu\s*400.000đ/m
    assert_select "a[href=?]", pms_calendar_path, text: "Xem trên lịch"
    assert_select "a[href=?]", new_pms_booking_path, text: "Đặt phòng khác"
  end

  test "a busy room sent anyway is refused by the model, as is a deposit over the total" do
    log_in users(:owner)
    assert_no_difference -> { Booking.count } do
      post pms_bookings_path, params: form(room_id: rooms(:limdim).id)
    end
    assert_response :unprocessable_entity
    assert_select "#dates_error", text: /Trùng lịch đêm 01\/10–02\/10 với Anh Minh/

    post pms_bookings_path, params: form(room_id: rooms(:garden).id, deposit: "600k")
    assert_response :unprocessable_entity
    assert_select "#deposit_error", text: /không được lớn hơn tiền phòng/
    assert_select "input[name='booking[guest_name]'][value='Cô Ba']"
  end

  test "staff book too, but cannot set the price" do
    places(:tomo).place_memberships.create!(user: users(:admin), role: "staff")
    log_in users(:admin)
    get new_pms_booking_path
    assert_select "input[name='booking[price]']", 0
    assert_select "#quote_footer", text: /1 đêm · còn thu/
    post pms_bookings_path, params: form(room_id: rooms(:garden).id, price: "1k")
    assert_equal 250_000, Booking.last.price
  end

  test "another homestay's room or booking is not found; no homestay, no form" do
    other = Room.create!(place: places(:hiuhill), name: "Đồi", max_guests: 2)
    stay = other.bookings.create!(start_date: "2026-10-02", end_date: "2026-10-03", guest_name: "Khách khác")
    log_in users(:owner)
    assert_no_difference -> { Booking.count } do
      post pms_bookings_path, params: form(room_id: other.id)
    end
    assert_response :not_found
    get saved_pms_booking_path(stay)
    assert_response :not_found

    log_in users(:admin) # a member of no homestay
    get new_pms_booking_path
    assert_response :not_found
  end
end
