require "test_helper"

# Đưa đón sân bay in the PWA (#307): the legs on Yêu cầu đặt phòng and the booking, Đã đón for anyone at the desk.
class Pms::TransfersTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 10, 1, 12)
    rooms(:garden).update!(room_type: "double", price: 400_000)
    @place = places(:tomo)
    site_ready(@place)
    @place.update!(site_open: true, transfer_partner: true, driver_phone: "0912 345 678")
  end

  def ask(transfer = { arrival: { time: "14:30", flight: "vj123" }, departure: true }, **attrs)
    @place.book_online(room_type: "double", start_date: "2026-10-05", end_date: "2026-10-07", guests: 2, guest_name: "Chị Hoa",
      guest_phone: "0905 111 333", transfer:, **attrs)
  end

  test "a request with a pickup shows the legs and the driver; one without shows nothing; not markable before Nhận" do
    request, plain = ask, ask(nil, guest_name: "Anh Tú", start_date: "2026-10-10", end_date: "2026-10-11")
    log_in users(:owner)
    get pms_booking_requests_path
    assert_select "##{dom_id(request)}", text: /Đưa đón sân bay.*Đón ở sân bay Phú Bài\s*Chờ đón.*T2 05\/10 · máy bay đến 14:30 · chuyến VJ123 · 200.000đ khách trả tiền mặt.*Đưa ra sân bay Phú Bài\s*Chờ đưa.*T4 07\/10 · 200.000đ.*Tài xế đối tác\s*0912345678/m
    assert_select "##{dom_id(request)} a[href='tel:0912345678']"
    assert_select "##{dom_id(request)} a[href='https://zalo.me/0912345678']"
    assert_select "##{dom_id(request)} form[action^='/dua-don']", 0
    assert_select "##{dom_id(plain)}", text: /Đưa đón/, count: 0

    post pms_transfer_done_path(request.transfers.first)
    assert_redirected_to pms_booking_requests_path
    assert_equal "Nhận yêu cầu đặt phòng trước", flash[:alert]
    assert request.transfers.first.reload.pending?
  end

  test "past its deadline, before BookingRequest.expire runs, a request no longer shows the driver" do
    request = ask
    travel 31.minutes
    log_in users(:owner)
    get pms_booking_requests_path(loc: "tu-choi")
    assert_select "##{dom_id(request)}", text: /Đón ở sân bay Phú Bài/
    assert_select "##{dom_id(request)}", text: /Tài xế đối tác/, count: 0
  end

  test "a declined request shows its pickup as cancelled, without the driver" do
    request = ask
    request.decline(reason: "dates")
    log_in users(:owner)
    get pms_booking_requests_path(loc: "tu-choi")
    assert_select "##{dom_id(request)}", text: /Đón ở sân bay Phú Bài\s*Đã huỷ.*Đưa ra sân bay Phú Bài\s*Đã huỷ/m
    assert_select "##{dom_id(request)}", text: /Tài xế đối tác/, count: 0
  end

  test "staff mark Đã đón on the booking; a done or cancelled leg can't be marked again" do
    request = ask
    assert request.accept(room: rooms(:garden), deposit_percent: 0)
    booking = request.booking
    arrival, departure = request.transfers.order(:kind)
    @place.place_memberships.create!(user: users(:admin), role: "staff")
    log_in users(:admin)
    get pms_booking_path(booking)
    assert_select "#dua-don", text: /Đón ở sân bay Phú Bài\s*Chờ đón.*Tài xế đối tác/m
    assert_select "#dua-don form", 0, "Not before its day"
    post pms_transfer_done_path(arrival)
    assert_equal "Chưa đến ngày 05/10", flash[:alert]
    assert arrival.reload.pending?

    travel_to Time.zone.local(2026, 10, 5, 15)
    get pms_booking_path(booking)
    assert_select "#dua-don form[action=?][data-turbo-confirm*='200.000đ'] button", pms_transfer_done_path(arrival), text: "Đã đón · đã thu tiền mặt"

    post pms_transfer_done_path(arrival), headers: { "HTTP_REFERER" => pms_booking_url(booking) }
    assert_redirected_to pms_booking_path(booking)
    assert_equal "Đã đón khách ở sân bay", flash[:toast]
    assert arrival.reload.done?
    follow_redirect!
    assert_select "##{dom_id(arrival)}", text: /Đã đón/
    assert_select "##{dom_id(arrival)} form", 0
    post pms_transfer_done_path(arrival)
    assert_equal "Chuyến đưa đón này đã xong", flash[:alert]

    booking.update!(status: "cancelled", cancel_reason: "Khách huỷ")
    post pms_transfer_done_path(departure)
    assert_equal "Chuyến đưa đón này đã huỷ", flash[:alert]
    assert departure.reload.cancelled?
    get pms_booking_path(booking)
    assert_select "#dua-don", text: /Tài xế đối tác/, count: 0
  end

  test "a booking without a pickup shows no block; another homestay's leg is 404" do
    log_in users(:owner)
    get pms_booking_path(bookings(:limdim_confirmed))
    assert_select "#dua-don", 0

    places(:hiuhill).update!(transfer_partner: true)
    other = places(:hiuhill).transfers.create!(kind: "departure", date: "2026-10-05", price: 200_000)
    post pms_transfer_done_path(other)
    assert_response :not_found
    assert other.reload.pending?
  end
end
