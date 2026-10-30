require "test_helper"

class V1::BookingSiteControllerTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 10, 1, 12) # limdim booked 01–03/10 by Anh Minh
    rooms(:garden).update!(room_type: "double", price: 400_000)
    rooms(:limdim).update!(room_type: "family", price: 500_000)
    @place = places(:tomo)
    @place.update!(bank_name: "Vietcombank", bank_account: "0123456789", bank_holder: "NGUYEN THI LAN", site_open: true, site_hidden_room_types: [ "family" ])
  end

  def body = response.parsed_body
  def guest = { room_type: "double", start_date: "2026-10-01", end_date: "2026-10-03", guests: 2, guest_name: "Chị Hoa", guest_phone: "0905111333" }

  test "the offer: shown room types with rooms left and the cheapest stay, no guest data" do
    get v1_booking_site_path(@place.slug, from: "2026-10-01", to: "2026-10-03"), headers: { "Origin" => "https://hueni.me" }
    assert_response :success
    assert_equal "https://hueni.me", response.headers["Access-Control-Allow-Origin"]
    assert_equal [ { "key" => "double", "label" => "Phòng đôi", "max_guests" => 2, "left" => 1, "total" => 800_000 } ], body["room_types"]
    assert_equal [ true, 30, 30, 20 ], body.values_at("open", "deposit_percent", "hold_minutes", "cutoff_hour")
    assert_no_match "Anh Minh", response.body

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
end
