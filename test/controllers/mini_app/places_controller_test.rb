require "test_helper"

# Mini App read endpoints (#153).
class MiniApp::PlacesControllerTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 10, 20, 10)
    rooms(:limdim).update!(price: 500_000, weekend_price: 600_000, note: "Chìa khoá ở quầy", room_type: "double", amenities: %w[ac balcony])
    @arriving = rooms(:limdim).bookings.create!(start_date: "2026-10-20", end_date: "2026-10-22", guest_name: "Chị Hoa", guests: 2)
    @arriving.payments.create!(amount: 300_000, payment_method: "bank")
    @arriving.charges.create!(name: "Xe máy", unit_price: 120_000, unit: "ngày", quantity: 2)
    @staying = rooms(:garden).bookings.create!(start_date: "2026-10-18", end_date: "2026-10-21", guest_name: "Anh Tuấn")
    @staying.update_columns(checked_in_at: Time.zone.local(2026, 10, 18, 14))
    @ota = rooms(:limdim).bookings.create!(start_date: "2026-10-21", end_date: "2026-10-23", source: "ical", uid: "ota-1", calendar_feed: calendar_feeds(:limdim_airbnb))
    @owner_token = users(:owner).api_tokens.create!.token
    @staff = User.create!(name: "Bé Na", phone_number: "0987654321", password: "password123")
    places(:tomo).place_memberships.create!(user: @staff, role: "staff")
    @staff_token = @staff.api_tokens.create!.token
  end

  def get_as(token, path) = get(path, headers: { "Authorization" => "Bearer #{token}" })
  def body = response.parsed_body

  test "rooms: owners get prices and the room note, staff do not" do
    get_as @owner_token, rooms_api_v1_place_path(places(:tomo))
    assert_response :success
    limdim = body["rooms"].find { it["id"] == rooms(:limdim).id }
    assert_equal({ "price" => 500_000, "weekend_price" => 600_000, "note" => "Chìa khoá ở quầy", "kind" => "Phòng đôi",
                   "amenities" => [ "Máy lạnh", "Ban công" ], "housekeeping" => "clean" }, limdim.slice("price", "weekend_price", "note", "kind", "amenities", "housekeeping"))

    get_as @staff_token, rooms_api_v1_place_path(places(:tomo))
    assert_response :success
    body["rooms"].each { assert_empty it.keys & %w[price weekend_price note] }
  end

  test "today: arrivals, guests in, OTA conflict; Ngày mai with ?day=mai" do
    get_as @owner_token, today_api_v1_place_path(places(:tomo))
    assert_response :success
    assert_equal [ @arriving.id ], body["arrivals"].pluck("id")
    assert_equal [ @staying.id ], body["in_house"].pluck("id")
    assert_equal 500_000, body["arrivals"].sole["price"]
    assert_equal "DP-0001", body["arrivals"].sole["code"]
    assert_equal [ [ "error", @arriving.id, "2026-10-21" ], [ "stay", @staying.id, nil ] ], body["issues"].map { it.values_at("kind", "booking_id", "date") }

    get_as @staff_token, today_api_v1_place_path(places(:tomo), day: "mai")
    assert_response :success
    assert_equal "2026-10-21", body["date"]
    assert_equal [ @ota.id ], body["arrivals"].pluck("id")
    assert_equal [ @staying.id ], body["departures"].pluck("id")
    assert_equal "airbnb", body["arrivals"].sole["provider"]
    body.values_at("arrivals", "departures", "in_house").flatten.each { assert_empty it.keys & %w[price weekend_price] }
  end

  test "board: each room's state today" do
    get_as @staff_token, board_api_v1_place_path(places(:tomo))
    assert_response :success
    days = body["days"].index_by { it.dig("room", "name") }
    assert_equal [ "arriving", @arriving.id, @ota.id ], days["Limdim"].values_at("state").push(days["Limdim"].dig("booking", "id"), days["Limdim"].dig("next", "id"))
    assert_equal [ "occupied", @staying.id ], [ days["Garden"]["state"], days["Garden"].dig("booking", "id") ]
    assert_not days["Limdim"]["booking"].key?("price")
  end

  test "calendar: bookings in the range, conflicts, range capped" do
    get_as @owner_token, calendar_api_v1_place_path(places(:tomo), from: "2026-10-19", to: "2027-06-01")
    assert_response :success
    assert_equal [ "2026-10-19", "2026-12-20" ], body.values_at("from", "to")
    assert_equal [ @staying.id, @arriving.id, @ota.id ], body["bookings"].pluck("id")
    assert_equal [ { "ota_id" => @ota.id, "manual_id" => @arriving.id } ], body["conflicts"]
    assert_equal false, body["bookings"].find { it["id"] == @arriving.id }["awaiting_deposit"]
  end

  test "booking detail: payments, services, totals; staff see totals, not the nightly quote" do
    get_as @owner_token, api_v1_booking_path(@arriving)
    assert_response :success
    assert_equal [ 500_000, 1_000_000, 1_240_000, 300_000, 940_000 ], body.values_at("price", "room_total", "total", "paid", "due")
    assert_equal [ 300_000, "bank" ], body["payments"].sole.values_at("amount", "method")
    assert_equal [ "Xe máy", 120_000, 2, 240_000 ], body["charges"].sole.values_at("name", "price", "qty", "amount")

    get_as @staff_token, api_v1_booking_path(@arriving)
    assert_response :success
    assert_equal 940_000, body["due"]
    assert_empty body.keys & %w[price weekend_price]

    get_as @owner_token, api_v1_booking_path(@ota)
    assert_response :success
    assert_nil body["due"] # paid on the OTA
  end

  test "another owner's homestay and bookings are 404; no token is 401" do
    other = places(:hiuhill).rooms.create!(name: "Đồi", max_guests: 2)
    booking = other.bookings.create!(start_date: "2026-10-20", end_date: "2026-10-21")
    %w[rooms today board calendar].each do |action|
      get_as @owner_token, "/api/v1/places/#{places(:hiuhill).id}/#{action}"
      assert_response :not_found
    end
    get_as @staff_token, api_v1_booking_path(booking)
    assert_response :not_found
    assert_equal "not_found", body["error"]

    get rooms_api_v1_place_path(places(:tomo))
    assert_response :unauthorized
  end
end
