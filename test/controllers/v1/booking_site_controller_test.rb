require "test_helper"

class V1::BookingSiteControllerTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 10, 1, 12) # limdim booked 01–03/10 by Anh Minh
    rooms(:garden).update!(room_type: "double", price: 400_000)
    rooms(:limdim).update!(room_type: "family", price: 500_000)
    @place = places(:tomo)
    site_ready(@place)
    @place.update!(site_mode: "auto", site_open: true, site_hidden_room_ids: [ rooms(:limdim).id ])
  end

  def body = response.parsed_body
  def guest = { room_type: "double", start_date: "2026-10-01", end_date: "2026-10-03", guests: 2, guest_name: "Chị Hoa", guest_phone: "0905111333" }

  test "the offer: shown room types with rooms left and the cheapest stay, no guest data" do
    get v1_booking_site_path(@place.slug, from: "2026-10-01", to: "2026-10-03"), headers: { "Origin" => "https://hueni.me" }
    assert_response :success
    assert_equal "https://hueni.me", response.headers["Access-Control-Allow-Origin"]
    assert_equal [ { "key" => "double", "label" => "Phòng đôi", "max_guests" => 2, "left" => 1, "total" => 800_000 } ], body["room_types"]
    assert_equal [ true, 30, 30, 20 ], body.values_at("open", "deposit_percent", "hold_minutes", "cutoff_hour")
    assert_equal [ "auto", 30, "14:00", "12:00", "Không hút thuốc trong phòng." ], body.values_at("mode", "reply_minutes", "check_in", "check_out", "rules")
    assert_equal [ { "id" => rooms(:garden).id, "name" => "Garden", "room_type" => "double", "max_guests" => 2, "free" => true, "total" => 800_000 } ], body["rooms"]
    assert_no_match "Anh Minh", response.body
    get v1_booking_site_path(@place.slug)
    assert_equal [ nil, nil ], body["rooms"].first.values_at("free", "total")

    @place.update!(site_open: false)
    get v1_booking_site_path(@place.slug)
    assert_equal({ "name" => "tomo homestay", "open" => false }, body)
    get v1_booking_site_path("khong-co")
    assert_response :not_found
  end

  test "a guest books, gets a status link with the bank to pay; the answer never echoes the guest" do
    post v1_booking_site_bookings_path(@place.slug), params: { booking: guest }, as: :json
    assert_response :created
    booking = Booking.last
    assert_equal [ "held", "Phòng đôi", 800_000, 240_000, "DP0001", "0123456789" ],
      [ body["status"], body["room_type"], body["total"], body["deposit"], body.dig("bank", "content"), body.dig("bank", "account") ]
    assert_no_match "Chị Hoa", response.body
    assert_no_match "0905111333", response.body
    assert_equal "Khách đặt online", Activity.lines(booking.versions).first.actor

    booking.payments.create!(amount: 240_000, payment_method: "bank")
    get v1_booking_site_status_path(body["token"])
    assert_equal [ "confirmed", 240_000, nil ], body.values_at("status", "paid", "bank")
    get v1_booking_site_status_path("nope")
    assert_response :not_found
  end

  test "refusals: full, closed type, honeypot; the preflight allows JSON POSTs" do
    post v1_booking_site_bookings_path(@place.slug), params: { booking: guest.merge(room_type: "family") }, as: :json
    assert_response :unprocessable_entity
    post v1_booking_site_bookings_path(@place.slug), params: { booking: guest.merge(website: "http://spam") }, as: :json
    assert_response :unprocessable_entity
    post v1_booking_site_bookings_path(@place.slug), params: { booking: guest }, as: :json
    post v1_booking_site_bookings_path(@place.slug), params: { booking: guest.merge(guest_name: "Anh Tú") }, as: :json
    assert_equal [ Place::SITE_FULL ], body.dig("errors", "base")
    assert_equal 1, Booking.where(online: true).count

    process :options, v1_booking_site_bookings_path(@place.slug), headers: { "Origin" => "https://hueni.me", "Access-Control-Request-Method" => "POST" }
    assert_response :no_content
    assert_equal [ "https://hueni.me", "Content-Type" ], response.headers.values_at("Access-Control-Allow-Origin", "Access-Control-Allow-Headers")
  end

  test "approve mode: the request is pending, holds the last room on hue-ni only; its link shows declined, expired or the booking" do
    @place.update!(site_mode: "approve")
    post v1_booking_site_bookings_path(@place.slug), params: { booking: guest }, as: :json
    assert_response :created
    assert_equal [ "pending", "2026-10-01T12:30:00.000+07:00", "Phòng đôi", nil ], body.values_at("status", "reply_by", "room_type", "reason")
    assert_match(/\AYC-/, body["code"])
    assert_no_match "Chị Hoa", response.body
    assert_no_match "0905111333", response.body
    token = body["token"]
    request = BookingRequest.sole

    get v1_booking_site_path(@place.slug, from: "2026-10-01", to: "2026-10-03")
    assert_equal [ 0, nil ], body["room_types"].first.values_at("left", "total")
    get v1_vacancy_path
    assert_equal 1, body.dig("places", @place.slug, "left"), "the PMS still sees the room free"

    request.decline(reason: "full", suggested_start_date: "2026-10-05", suggested_end_date: "2026-10-07")
    get v1_booking_site_status_path(token)
    assert_equal [ "declined", "Hết phòng loại này", { "start_date" => "2026-10-05", "end_date" => "2026-10-07" }, nil ],
      body.values_at("status", "reason", "suggested", "phone")

    post v1_booking_site_bookings_path(@place.slug), params: { booking: guest.merge(guest_name: "Anh Tú") }, as: :json
    late = body["token"]
    travel 31.minutes
    get v1_booking_site_status_path(late)
    assert_equal "expired", body["status"]

    post v1_booking_site_bookings_path(@place.slug), params: { booking: guest.merge(guest_name: "Chị Mai") }, as: :json
    BookingRequest.last.accept(room: rooms(:garden), deposit_percent: 50)
    get v1_booking_site_status_path(body["token"])
    assert_equal [ "held", 400_000, "0123456789", nil ], [ body["status"], body["deposit"], body.dig("bank", "account"), body["phone"] ]
    assert_match(/\ADP-/, body["code"])
    @place.update!(site_show_phone: true)
    get v1_booking_site_status_path(token)
    assert_nil body["phone"], "declined: no phone"
    get v1_booking_site_status_path(BookingRequest.last.signed_id(purpose: :booking_site))
    assert_equal "+84 338 268 606", body["phone"]
  end

  test "a guest picks a room (#290): the request holds it, its status names it; another homestay's room is refused" do
    @place.update!(site_mode: "approve")
    pick = guest.except(:room_type).merge(room_id: rooms(:garden).id)
    post v1_booking_site_bookings_path(@place.slug), params: { booking: pick }, as: :json
    assert_response :created
    assert_equal [ "pending", "Phòng đôi", "Garden" ], body.values_at("status", "room_type", "room")
    assert_equal rooms(:garden), BookingRequest.sole.room

    get v1_booking_site_path(@place.slug, from: "2026-10-01", to: "2026-10-03")
    assert_equal [ false ], body["rooms"].pluck("free")
    assert_equal 0, body["room_types"].first["left"]

    other = places(:hiuhill).rooms.create!(name: "Sen", room_type: "double", max_guests: 2)
    post v1_booking_site_bookings_path(@place.slug), params: { booking: pick.merge(room_id: other.id) }, as: :json
    assert_response :unprocessable_entity
    assert_equal [ "Phòng này không nhận đặt online" ], body.dig("errors", "base")
    post v1_booking_site_bookings_path(@place.slug), params: { booking: pick.merge(guest_name: "Anh Tú") }, as: :json
    assert_equal [ Place::SITE_ROOM_FULL ], body.dig("errors", "base")
  end
end
