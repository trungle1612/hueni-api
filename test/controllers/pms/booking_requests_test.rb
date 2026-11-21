require "test_helper"

# Yêu cầu đặt phòng in the PWA (#284): requests from hue-ni answered with Nhận / Từ chối by owners and staff.
class Pms::BookingRequestsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    travel_to Time.zone.local(2026, 10, 1, 12) # limdim booked 01–03/10 by Anh Minh
    rooms(:garden).update!(room_type: "double", price: 400_000)
    rooms(:limdim).update!(room_type: "double", price: 500_000)
    @place = places(:tomo)
    site_ready(@place)
    @place.update!(site_open: true, site_deposit_percent: 30)
  end

  def ask(**attrs) = @place.book_online(room_type: "double", start_date: "2026-10-01", end_date: "2026-10-02", guests: 2,
    guest_name: "Chị Hoa", guest_phone: "0905 111 333", note: "Mình đến khoảng 21h", **attrs)

  test "a new request: the push opens it under Chờ trả lời with its countdown, free rooms and estimate; Thêm counts it" do
    request = ask
    perform_enqueued_jobs
    log_in users(:owner)
    get pms_open_notification_path(Notification.last.key, co_so: @place.slug)
    assert_redirected_to pms_booking_requests_path
    follow_redirect!
    assert_response :success
    assert_select "nav a[aria-current=page]", text: "Chờ trả lời · 1"
    assert_select "##{dom_id(request)}", text: /Chị Hoa.*hue-ni · gửi 12:00 · YC-\d{4}.*Còn 30 phút.*T5 01\/10 – T6 02\/10 · 1 đêm.*Phòng đôi · 2 khách.*400.000đ.*Mình đến khoảng 21h.*Phòng đôi: còn 1 phòng trống/m
    assert_select "##{dom_id(request)} [data-countdown-seconds-value='1800']"
    assert_select "meta[name=turbo-cache-control][content=no-cache]", 1, "Back must not restart the countdown from a cached page"
    assert_select "##{dom_id(request, :accept)} input[name=room_id][value='#{rooms(:garden).id}'][checked]"
    assert_select "##{dom_id(request, :accept)} input[name=room_id][value='#{rooms(:limdim).id}'][disabled]"
    assert_select "##{dom_id(request, :accept)} input[name=room_id][data-deposits*='120.000đ']"
    assert_select "##{dom_id(request, :accept)} input[name=deposit_percent][value='30'][checked]"

    get pms_more_path
    assert_select "main a[href=?]", pms_booking_requests_path, text: /Yêu cầu đặt phòng\s*1 chờ trả lời/
    get pms_listing_path
    assert_select "a#requests[href=?]", pms_booking_requests_path
  end

  test "a picked room (#290) shows on the card and is preselected in Nhận" do
    request = ask(room_id: rooms(:limdim).id, start_date: "2026-10-05", end_date: "2026-10-06")
    log_in users(:owner)
    get pms_booking_requests_path
    assert_select "##{dom_id(request)}", text: /Khách chọn\s*Phòng Limdim/
    assert_select "##{dom_id(request, :accept)}", text: /Khách chọn phòng Limdim\s/
    assert_select "##{dom_id(request, :accept)} input[name=room_id][value='#{rooms(:limdim).id}'][checked]"
    assert_select "##{dom_id(request, :accept)} input[name=room_id][value='#{rooms(:garden).id}']:not([checked])"
  end

  test "Nhận books the room, held for the deposit, and links the booking under Đã nhận" do
    request = ask
    log_in users(:owner)
    post accept_pms_booking_request_path(request), params: { room_id: rooms(:garden).id, deposit_percent: 30 }
    assert_redirected_to pms_booking_requests_path(loc: "da-nhan")
    booking = request.reload.booking
    assert_equal [ "accepted", 30, rooms(:garden), true ], [ request.status, request.deposit_percent, booking.room, booking.held? ]
    follow_redirect!
    assert_select ".pms-toast", text: "Đã nhận, tạo đặt phòng #{booking.code} cho Chị Hoa"
    assert_select "##{dom_id(request)}", text: /Đã nhận.*phòng Garden · chờ cọc 120.000đ đến 12:30/m
    assert_select "##{dom_id(request)} a[href=?]", pms_booking_path(booking), text: "Xem đặt phòng"
  end

  test "a room taken meanwhile: Nhận shows the model's message and the request stays open" do
    request = ask
    rooms(:garden).bookings.create!(start_date: "2026-10-01", end_date: "2026-10-02", guest_name: "Khách vãng lai")
    log_in users(:owner)
    post accept_pms_booking_request_path(request), params: { room_id: rooms(:garden).id, deposit_percent: 0 }
    assert_redirected_to pms_booking_requests_path
    follow_redirect!
    assert_select "[role=alert]", text: /trùng/i
    assert request.reload.pending?
    assert_select "##{dom_id(request)}", text: /Phòng đôi: hết phòng từ ngày 01\/10\./
    assert_select "##{dom_id(request)} a[href=?]", pms_calendar_path(from: "2026-10-01"), text: "Xem lịch"
    assert_select "##{dom_id(request, :accept)}", count: 0
  end

  test "full because of an OTA: says which, and Từ chối · Hết phòng suggests the next free dates" do
    request = ask(start_date: "2026-10-02", end_date: "2026-10-03")
    rooms(:garden).bookings.create!(start_date: "2026-10-02", end_date: "2026-10-04", source: "ical", uid: "x@airbnb", calendar_feed: calendar_feeds(:limdim_airbnb))
    log_in users(:owner)
    get pms_booking_requests_path
    assert_select "##{dom_id(request)}", text: /Phòng đôi: hết phòng từ ngày 02\/10 \(đã có khách đặt qua Airbnb\)/
    assert_select "##{dom_id(request, :decline)} input[name=reason][value=full][checked]"
    assert_select "##{dom_id(request, :decline)}", text: /Phòng đôi còn trống 03 – 04\/10/
    assert_select "##{dom_id(request, :decline)} input[name=suggested_start_date][value='2026-10-03']"

    post decline_pms_booking_request_path(request), params: { reason: "full", suggested_start_date: "2026-10-03", suggested_end_date: "2026-10-04" }
    assert_redirected_to pms_booking_requests_path(loc: "tu-choi")
    assert_equal [ "declined", "full", Date.new(2026, 10, 3) ], request.reload.values_at(:status, :decline_reason, :suggested_start_date)
    follow_redirect!
    assert_select "##{dom_id(request)}", text: /Đã từ chối.*Từ chối: hết phòng loại này · khách được gợi ý 03 – 04\/10/m
  end

  test "Nhận refuses a missing room, a blank Cọc and a deposit with no bank account" do
    request = ask
    log_in users(:owner)
    post accept_pms_booking_request_path(request), params: { room_id: "", deposit_percent: 0 }
    follow_redirect!
    assert_select "[role=alert]", text: "Chọn phòng để nhận"
    post accept_pms_booking_request_path(request), params: { room_id: rooms(:garden).id }
    follow_redirect!
    assert_select "[role=alert]", text: "Cọc không hợp lệ"
    @place.update_columns(bank_account: nil)
    post accept_pms_booking_request_path(request), params: { room_id: rooms(:garden).id, deposit_percent: 30 }
    follow_redirect!
    assert_select "[role=alert]", text: /Cần tài khoản chuyển khoản/
    assert_select "##{dom_id(request, :accept)} input[name=deposit_percent][value='30'][disabled]"
    assert request.reload.pending?
  end

  test "a hold past midnight shows its date, an ended one says so; closed requests show no Tạm tính" do
    @place.update!(site_hold_minutes: 120)
    travel_to Time.zone.local(2026, 10, 1, 23)
    request = ask(start_date: "2026-10-05", end_date: "2026-10-06")
    expired = ask(start_date: "2026-10-07", end_date: "2026-10-08")
    expired.update_columns(status: "expired")
    request.accept(room: rooms(:garden), deposit_percent: 30)
    log_in users(:owner)
    get pms_booking_requests_path(loc: "da-nhan")
    assert_select "##{dom_id(request)}", text: /chờ cọc 120.000đ đến 01:00 02\/10/
    travel 3.hours
    get pms_booking_requests_path(loc: "da-nhan")
    assert_select "##{dom_id(request)}", text: /hết hạn giữ chỗ/
    get pms_booking_requests_path(loc: "tu-choi")
    assert_select "##{dom_id(expired)}", text: /Ngày/
    assert_select "##{dom_id(expired)}", text: /Tạm tính/, count: 0
  end

  test "each night has a room free but no one room the whole stay: says so, names no night" do
    request = ask(start_date: "2026-10-03", end_date: "2026-10-05")
    rooms(:garden).bookings.create!(start_date: "2026-10-04", end_date: "2026-10-05", guest_name: "Khách A")
    rooms(:limdim).bookings.create!(start_date: "2026-10-03", end_date: "2026-10-04", guest_name: "Khách B")
    log_in users(:owner)
    get pms_booking_requests_path
    assert_select "##{dom_id(request)}", text: /Phòng đôi: không phòng nào trống suốt những ngày này\./
  end

  test "the Hết phòng suggestion skips dates other pending requests hold on hue-ni" do
    request = ask(start_date: "2026-10-02", end_date: "2026-10-03")
    rooms(:garden).bookings.create!(start_date: "2026-10-02", end_date: "2026-10-04", guest_name: "Khách A")
    ask(guest_name: "Anh Tú", start_date: "2026-10-03", end_date: "2026-10-04") # holds limdim, the one room free 03–04
    log_in users(:owner)
    get pms_booking_requests_path
    assert_select "##{dom_id(request, :decline)}", text: /Phòng đôi còn trống 04 – 05\/10/
  end

  test "Từ chối needs a reason; suggested dates go with Hết phòng only" do
    request = ask
    log_in users(:owner)
    post decline_pms_booking_request_path(request), params: { reason: "" }
    assert_redirected_to pms_booking_requests_path
    follow_redirect!
    assert_select "[role=alert]", text: /Lý do từ chối/
    assert request.reload.pending?

    post decline_pms_booking_request_path(request), params: { reason: "rules", suggested_start_date: "2026-10-03", suggested_end_date: "2026-10-04" }
    assert_equal [ "declined", "rules", nil ], request.reload.values_at(:status, :decline_reason, :suggested_start_date)
  end

  test "past the deadline: Hết hạn, no longer answerable; the list keeps 30 days" do
    request = ask
    old = ask(guest_name: "Anh Tú", start_date: "2026-10-05", end_date: "2026-10-06")
    old.update_columns(status: "expired", created_at: 31.days.ago)
    travel 31.minutes
    log_in users(:owner)
    get pms_booking_requests_path
    assert_select "main", text: /Đã trả lời hết yêu cầu/
    get pms_booking_requests_path(loc: "tu-choi")
    assert_select "nav a[aria-current=page]", text: "Từ chối, hết hạn · 1"
    assert_select "##{dom_id(request)}", text: /Hết hạn.*Hết hạn sau 30 phút không trả lời/m
    assert_select "##{dom_id(old)}", count: 0
    post accept_pms_booking_request_path(request), params: { room_id: rooms(:garden).id, deposit_percent: 0 }
    follow_redirect!
    assert_select "[role=alert]", text: BookingRequest::CLOSED
  end

  test "staff answer requests; another homestay's request is 404; no homestay 404" do
    @place.place_memberships.create!(user: users(:admin), role: "staff")
    first, second = ask, ask(start_date: "2026-10-05", end_date: "2026-10-06")
    log_in users(:admin)
    get pms_booking_requests_path
    assert_response :success
    assert_select "a[href=?]", pms_listing_path, count: 0
    post accept_pms_booking_request_path(first), params: { room_id: rooms(:garden).id, deposit_percent: 0 }
    assert_redirected_to pms_booking_requests_path(loc: "da-nhan")
    post decline_pms_booking_request_path(second), params: { reason: "dates" }
    assert_redirected_to pms_booking_requests_path(loc: "tu-choi")
    assert_equal %w[accepted declined], [ first.reload.status, second.reload.status ]

    other = places(:hiuhill).booking_requests.create!(room_type: "double", reply_by: 30.minutes.from_now, start_date: "2026-10-05",
      end_date: "2026-10-06", guests: 2, guest_name: "Chị Lan", guest_phone: "0905000111")
    post accept_pms_booking_request_path(other), params: { room_id: rooms(:garden).id, deposit_percent: 0 }
    assert_response :not_found
    post decline_pms_booking_request_path(other), params: { reason: "dates" }
    assert_response :not_found
    assert other.reload.pending?

    @place.place_memberships.where(user: users(:admin)).delete_all
    post decline_pms_booking_request_path(ask(start_date: "2026-10-07", end_date: "2026-10-08")), params: { reason: "dates" }
    assert_response :not_found
  end
end
