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

  test "Nhận books the room, held for the deposit, and links the booking under Đã nhận" do
    request = ask
    log_in users(:owner)
    post accept_pms_booking_request_path(request), params: { room_id: rooms(:garden).id, deposit_percent: 30 }
    assert_redirected_to pms_booking_requests_path(loc: "da-nhan")
    booking = request.reload.booking
    assert_equal [ "accepted", 30, rooms(:garden), true ], [ request.status, request.deposit_percent, booking.room, booking.held? ]
    follow_redirect!
    assert_select ".pms-toast", text: "Đã nhận, đã tạo đặt phòng. Gọi hoặc nhắn Chị Hoa ngay"
    assert_select ".pms-toast form", 0, "the guest already sees the bank account: no Hoàn tác"
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
    post undo_pms_booking_request_path(second)
    assert_redirected_to pms_booking_requests_path
    assert second.reload.pending?

    other = places(:hiuhill).booking_requests.create!(room_type: "double", reply_by: 30.minutes.from_now, start_date: "2026-10-05",
      end_date: "2026-10-06", guests: 2, guest_name: "Chị Lan", guest_phone: "0905000111")
    post accept_pms_booking_request_path(other), params: { room_id: rooms(:garden).id, deposit_percent: 0 }
    assert_response :not_found
    post decline_pms_booking_request_path(other), params: { reason: "dates" }
    assert_response :not_found
    assert other.reload.pending?
    other.decline(reason: "dates")
    post undo_pms_booking_request_path(other)
    assert_response :not_found
    assert other.reload.declined?

    @place.place_memberships.where(user: users(:admin)).delete_all
    post decline_pms_booking_request_path(ask(start_date: "2026-10-07", end_date: "2026-10-08")), params: { reason: "dates" }
    assert_response :not_found
  end

  test "the guest's phone with Gọi and Nhắn Zalo on open and accepted requests only; Nhận sheet's message to copy" do
    open, accepted, declined, expired = ask, ask(start_date: "2026-10-05", end_date: "2026-10-06"),
      ask(start_date: "2026-10-07", end_date: "2026-10-08"), ask(start_date: "2026-10-09", end_date: "2026-10-10")
    accepted.accept(room: rooms(:garden), deposit_percent: 0)
    declined.decline(reason: "dates")
    expired.update_columns(status: "expired")
    log_in users(:owner)
    get pms_booking_requests_path
    assert_select "header", text: /Khách đang chờ bạn gọi hoặc nhắn Zalo/
    assert_select "##{dom_id(open)}", text: /Số của khách\s*0905 111 333/
    assert_select "##{dom_id(open)} a[href='tel:0905111333']", text: "Gọi"
    assert_select "##{dom_id(open)} a[href='https://zalo.me/0905111333'][target=_blank]", text: "Nhắn Zalo"
    assert_select "main", text: /Khách được báo: homestay sẽ gọi hoặc nhắn Zalo trong thời hạn trả lời. Quá hạn, yêu cầu tự hết hạn. Thời hạn đổi ở Hiển thị trên hue-ni./
    assert_select "##{dom_id(open, :accept)}", text: /Tin nhắn soạn sẵn · dán vào Zalo khi nhắn khách\s*Sao chép.*khách được báo là homestay sẽ liên hệ trong 30 phút.*Nhận yêu cầu/m
    assert_select "##{dom_id(open, :accept)} [data-controller=copy] [data-copy-target=source]", text: /đã nhận yêu cầu của bạn/
    assert_select "##{dom_id(open, :decline)}", text: /Trang yêu cầu của khách hiện lý do bạn chọn. Nên gọi hoặc nhắn khách một câu/
    get pms_booking_requests_path(loc: "da-nhan")
    assert_select "##{dom_id(accepted)} a[href='tel:0905111333']"
    get pms_booking_requests_path(loc: "tu-choi")
    assert_select "##{dom_id(declined)}"
    assert_select "##{dom_id(expired)}"
    assert_select "a[href^='tel:'], a[href^='https://zalo.me']", count: 0
    assert_select "main", text: /0905 111 333/, count: 0

    abroad = ask(start_date: "2026-10-11", end_date: "2026-10-12", guest_phone: "+84 905 111 444")
    get pms_booking_requests_path
    assert_select "##{dom_id(abroad)} a[href='tel:+84905111444']"
    assert_select "##{dom_id(abroad)} a[href='https://zalo.me/84905111444']"
  end

  test "Hoàn tác after Nhận removes the booking without a trace; the request waits again" do
    request = ask
    log_in users(:owner)
    post accept_pms_booking_request_path(request), params: { room_id: rooms(:garden).id, deposit_percent: 0 }
    follow_redirect!
    assert_select ".pms-toast form[action=?]", undo_pms_booking_request_path(request)
    booking = request.reload.booking
    assert_no_enqueued_jobs only: NotificationJob do
      post undo_pms_booking_request_path(request)
    end
    perform_enqueued_jobs # Đặt phòng mới, queued before the undo
    assert_redirected_to pms_booking_requests_path
    assert_equal [ "pending", nil, nil ], request.reload.values_at(:status, :booking_id, :deposit_percent)
    assert_not Booking.exists?(booking.id)
    assert_not PaperTrail::Version.exists?(item_type: "Booking", item_id: booking.id), "no Đặt phòng bị huỷ in Báo cáo or Nhật ký"
    assert_not Notification.exists?(booking_id: booking.id)
    assert_equal "pending", request.site_status
    follow_redirect!
    assert_select ".pms-toast", text: "Đã hoàn tác, yêu cầu chờ trả lời lại"
    assert_select "nav a[aria-current=page]", text: "Chờ trả lời · 1"
    assert_select "##{dom_id(request, :accept)}"
  end

  test "Hoàn tác after Từ chối: back under Chờ trả lời, reason and suggestion cleared" do
    request = ask(start_date: "2026-10-02", end_date: "2026-10-03")
    request.decline(reason: "full", suggested_start_date: "2026-10-03", suggested_end_date: "2026-10-04")
    log_in users(:owner)
    post undo_pms_booking_request_path(request)
    assert_equal [ "pending", nil, nil, nil ], request.reload.values_at(:status, :decline_reason, :suggested_start_date, :suggested_end_date)
    assert_equal "pending", request.site_status
  end

  test "Hoàn tác is refused once the booking was worked on, with a deposit asked, and after the undo window" do
    paid, edited, deposit = ask, ask(start_date: "2026-10-05", end_date: "2026-10-06"), ask(start_date: "2026-10-07", end_date: "2026-10-08")
    [ paid, edited ].each { it.accept(room: rooms(:garden), deposit_percent: 0) }
    deposit.accept(room: rooms(:garden), deposit_percent: 30)
    log_in users(:owner)
    paid.booking.payments.create!(amount: 100_000, payment_method: "cash").destroy! # added then deleted: still in Lịch sử
    edited.booking.update!(note: "Đến muộn")
    { paid => /đã được sửa, thu tiền/, edited => /đã được sửa, thu tiền/, deposit => /đã thấy tài khoản để chuyển cọc/ }.each do |request, message|
      post undo_pms_booking_request_path(request)
      assert_redirected_to pms_booking_requests_path(loc: "da-nhan")
      follow_redirect!
      assert_select "[role=alert]", text: message
      assert request.reload.accepted?
    end

    other = ask(start_date: "2026-10-09", end_date: "2026-10-10")
    other.decline(reason: "dates")
    travel (BookingRequest::UNDO_MINUTES + 1).minutes
    post undo_pms_booking_request_path(other)
    follow_redirect!
    assert_select "[role=alert]", text: "Đã quá thời gian hoàn tác"
    assert other.reload.declined?
  end
end
