require "test_helper"

# Mini App write endpoints (#154): same rules as /admin.
class MiniApp::BookingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 10, 20, 10)
    rooms(:limdim).update!(price: 500_000)
    rooms(:garden).update!(price: 300_000)
    @booking = rooms(:limdim).bookings.create!(start_date: "2026-10-20", end_date: "2026-10-22", guest_name: "Chị Hoa")
    @owner = users(:owner)
    @staff = User.create!(name: "Bé Na", phone_number: "0987654321", password: "password123")
    places(:tomo).place_memberships.create!(user: @staff, role: "staff")
    @tokens = { owner: @owner.api_tokens.create!.token, staff: @staff.api_tokens.create!.token }
  end

  def as(who, verb, path, params = {}) = send(verb, path, params:, headers: { "Authorization" => "Bearer #{@tokens.fetch(who)}" }, as: :json)
  def body = response.parsed_body

  test "create: owners quote the price and note the deposit; staff get the room's price and never see it" do
    as :owner, :post, api_v1_place_bookings_path(places(:tomo)),
      { booking: { room_id: rooms(:garden).id, start_date: "2026-10-21", end_date: "2026-10-23", guest_name: "Anh Tuấn", guests: 2, price: 280_000, deposit: 200_000, deposit_method: "bank" } }
    assert_response :created
    assert_equal [ 280_000, 560_000, 200_000, 360_000 ], body.values_at("price", "total", "paid", "due")
    assert_equal [ 200_000, "bank" ], body["payments"].sole.values_at("amount", "method")
    assert_equal @owner.id.to_s, PaperTrail::Version.where(item_type: "Booking").last.whodunnit

    as :staff, :post, api_v1_place_bookings_path(places(:tomo)),
      { booking: { room_id: rooms(:garden).id, start_date: "2026-10-25", end_date: "2026-10-26", price: 1 } }
    assert_response :created
    assert_nil body["price"]
    assert_equal 300_000, Booking.find(body["id"]).price
  end

  test "create and availability refuse a clash, naming it and the rooms still free" do
    as :staff, :get, availability_api_v1_place_path(places(:tomo)), { room_id: rooms(:limdim).id, start_date: "2026-10-21", end_date: "2026-10-23" }
    assert_response :success
    assert_equal false, body["available"]
    assert_match "Trùng lịch đêm 21/10 với Chị Hoa", body["problems"].sole
    assert_equal [ rooms(:garden).id ], body["free_room_ids"]

    as :staff, :get, availability_api_v1_place_path(places(:tomo)), { room_id: rooms(:limdim).id, start_date: "2026-10-21", end_date: "2026-10-23", booking_id: @booking.id }
    assert_equal [ true, [], [] ], body.values_at("available", "problems", "free_room_ids")

    as :staff, :post, api_v1_place_bookings_path(places(:tomo)), { booking: { room_id: rooms(:limdim).id, start_date: "2026-10-21", end_date: "2026-10-23" } }
    assert_response :unprocessable_entity
    assert_equal "invalid", body["error"]
    assert_match "Trùng lịch", body.dig("errors", "base").sole
  end

  test "update: edit, cancel needs a reason, the refund is owners only, a checked-out stay is locked" do
    @booking.payments.create!(amount: 300_000, payment_method: "cash")
    as :staff, :patch, api_v1_booking_path(@booking), { booking: { guest_name: "Chị Hoa Lê", guests: 2 } }
    assert_response :success
    assert_equal "Chị Hoa Lê", body["guest_name"]

    as :staff, :patch, api_v1_booking_path(@booking), { booking: { status: "cancelled" } }
    assert_response :unprocessable_entity
    assert body.dig("errors", "cancel_reason").present?

    as :staff, :patch, api_v1_booking_path(@booking), { booking: { status: "cancelled", cancel_reason: "Khách huỷ" }, refund_method: "cash" }
    assert_response :success
    assert_equal [ "cancelled", 300_000 ], body.values_at("status", "paid") # staff can't refund: the money is kept

    as :owner, :patch, api_v1_booking_path(@booking), { booking: { status: "confirmed" } }
    as :owner, :patch, api_v1_booking_path(@booking), { booking: { status: "cancelled", cancel_reason: "Khách huỷ" }, refund_method: "bank" }
    assert_response :success
    assert_equal [ 0, -300_000 ], [ body["paid"], body["payments"].last["amount"] ]

    stay = rooms(:garden).bookings.create!(start_date: "2026-10-18", end_date: "2026-10-20", checked_in_at: 2.days.ago, checked_out_at: 1.hour.ago)
    as :owner, :patch, api_v1_booking_path(stay), { booking: { guest_name: "X" } }
    assert_response :unprocessable_entity
    assert_equal [ "Khách đã trả phòng, không sửa được đặt phòng." ], body.dig("errors", "base")
  end

  test "Giảm giá: staff up to 10%, owners up to the room total" do
    as :staff, :patch, discount_api_v1_booking_path(@booking), { booking: { discount: "20%", discount_reason: "Khách quen" } }
    assert_response :unprocessable_entity
    assert_match "tối đa 10%", body.dig("errors", "discount").sole

    as :owner, :patch, discount_api_v1_booking_path(@booking), { booking: { discount: "200k", discount_reason: "Khách quen" } }
    assert_response :success
    assert_equal [ { "amount" => 200_000, "reason" => "Khách quen" }, 800_000 ], body.values_at("discount", "total")
  end

  test "check-in asks for the head count, collects what is due; check-out frees the room; Hoàn tác is owners only" do
    as :staff, :post, check_in_api_v1_booking_path(@booking)
    assert_response :unprocessable_entity
    assert_equal [ "Số khách cần nhập khi nhận phòng" ], body.dig("errors", "guests")

    as :staff, :post, check_in_api_v1_booking_path(@booking), { guests: 2, collect: true }
    assert_response :success
    assert body["checked_in_at"]
    assert_equal [ 1_000_000, 0, "cash" ], [ body["paid"], body["due"], body["payments"].sole["method"] ]

    as :staff, :post, undo_check_in_api_v1_booking_path(@booking)
    assert_response :forbidden

    as :staff, :post, declare_api_v1_booking_path(@booking)
    assert body["declared_at"]
    as :staff, :post, move_api_v1_booking_path(@booking), { room_id: rooms(:garden).id }
    assert_response :success
    assert_equal rooms(:garden).id, body["room_id"]
    assert rooms(:limdim).reload.dirty?

    as :staff, :post, check_out_api_v1_booking_path(@booking)
    assert_response :success
    assert body["checked_out_at"]
    assert rooms(:garden).reload.dirty?

    as :owner, :post, undo_check_out_api_v1_booking_path(@booking)
    assert_response :success
    assert_nil body["checked_out_at"]
  end

  test "Không đến cancels with that reason" do
    travel 1.day
    as :staff, :post, no_show_api_v1_booking_path(@booking)
    assert_response :success
    assert_equal [ "cancelled", "Không đến" ], body.values_at("status", "cancel_reason")
  end

  test "payments: staff take money, refunds and deleting are owners only; services from the catalog" do
    as :staff, :post, api_v1_booking_payments_path(@booking), { payment: { amount: "300k", payment_method: "bank" } }
    assert_response :created
    payment = @booking.payments.sole
    as :staff, :post, api_v1_booking_payments_path(@booking), { payment: { amount: 100_000, payment_method: "cash", kind: "refund" } }
    assert_response :forbidden
    as :staff, :post, api_v1_booking_payments_path(@booking), { payment: { amount: 2_000_000, payment_method: "cash" } }
    assert_response :unprocessable_entity
    assert body.dig("errors", "amount").present?
    as :staff, :delete, api_v1_booking_payment_path(@booking, payment)
    assert_response :forbidden
    as :owner, :delete, api_v1_booking_payment_path(@booking, payment)
    assert_response :success
    assert_equal [], body["payments"]

    service = places(:tomo).services.create!(name: "Thuê xe máy", price: 150_000, unit: "ngày")
    as :staff, :get, services_api_v1_place_path(places(:tomo))
    assert_includes body["services"], { "id" => service.id, "name" => "Thuê xe máy", "price" => 150_000, "unit" => "ngày" }
    as :staff, :post, api_v1_booking_charges_path(@booking), { service_id: service.id, quantity: 2 }
    assert_response :created
    charge = body["charges"].sole
    assert_equal [ "Thuê xe máy", 300_000, 1_300_000 ], [ charge["name"], charge["amount"], body["total"] ]
    as :staff, :delete, api_v1_booking_charge_path(@booking, charge["id"])
    assert_equal [], body["charges"]
  end

  test "rooms: Dọn xong and Bảo trì, staff too" do
    rooms(:garden).dirty!
    as :staff, :post, clean_api_v1_room_path(rooms(:garden))
    assert_response :success
    assert_equal "clean", body["housekeeping"]

    as :staff, :patch, maintenance_api_v1_room_path(rooms(:garden)), { room: { maintenance_reason: "Hỏng máy lạnh", maintenance_until: "2026-10-25" } }
    assert_response :success
    assert_equal({ "reason" => "Hỏng máy lạnh", "until" => "2026-10-25" }, body["maintenance"])

    as :staff, :patch, maintenance_api_v1_room_path(rooms(:limdim)), { room: { maintenance_reason: "", maintenance_until: "2026-10-25" } }
    assert_response :unprocessable_entity
    assert body.dig("errors", "maintenance_reason").present?
  end

  test "another owner's homestay, booking and room are 404; OTA bookings can't be edited" do
    room = places(:hiuhill).rooms.create!(name: "Đồi", max_guests: 2)
    other = room.bookings.create!(start_date: "2026-10-20", end_date: "2026-10-21")
    as :owner, :post, api_v1_place_bookings_path(places(:hiuhill)), { booking: { room_id: room.id, start_date: "2026-10-22", end_date: "2026-10-23" } }
    assert_response :not_found
    as :owner, :post, api_v1_place_bookings_path(places(:tomo)), { booking: { room_id: room.id, start_date: "2026-10-22", end_date: "2026-10-23" } }
    assert_response :not_found
    as :owner, :patch, api_v1_booking_path(other), { booking: { guest_name: "X" } }
    assert_response :not_found
    as :owner, :post, check_in_api_v1_booking_path(other), { guests: 1 }
    assert_response :not_found
    as :owner, :post, api_v1_booking_payments_path(other), { payment: { amount: 1, payment_method: "cash" } }
    assert_response :not_found
    as :owner, :post, clean_api_v1_room_path(room)
    assert_response :not_found
    as :owner, :post, move_api_v1_booking_path(@booking), { room_id: room.id }
    assert_response :not_found

    ota = rooms(:limdim).bookings.create!(start_date: "2026-10-25", end_date: "2026-10-26", source: "ical", uid: "ota-1", calendar_feed: calendar_feeds(:limdim_airbnb))
    as :owner, :patch, api_v1_booking_path(ota), { booking: { guest_name: "X" } }
    assert_response :not_found

    as :owner, :post, api_v1_place_bookings_path(places(:tomo)), {}
    assert_response :bad_request
  end
end
