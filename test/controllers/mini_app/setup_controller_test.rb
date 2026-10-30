require "test_helper"

# Mini App homestay setup (#162): rooms, services catalog, commissions, bank, members. Owners write; staff read lists.
class MiniApp::SetupControllerTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 10, 20, 10)
    rooms(:limdim).update!(price: 500_000)
    @staff = User.create!(name: "Bé Na", phone_number: "0987654321", password: "password123")
    places(:tomo).place_memberships.create!(user: @staff, role: "staff")
    @tokens = { owner: users(:owner).api_tokens.create!.token, staff: @staff.api_tokens.create!.token }
  end

  def as(who, verb, path, params = {}) = send(verb, path, params:, headers: { "Authorization" => "Bearer #{@tokens.fetch(who)}" }, as: (:json unless verb == :get))
  def body = response.parsed_body

  test "rooms: owners create with keys, see the labels back; update tells what to check; staff 403" do
    as :owner, :post, api_v1_place_rooms_path(places(:tomo)),
      { room: { name: "Sen", max_guests: 2, price: "350k", weekend_price: "400k", floor: 2, room_type: "double", amenities: %w[ac balcony], note: "Chìa ở quầy" } }
    assert_response :created
    assert_equal [ "Sen", 350_000, "double", "Phòng đôi", %w[ac balcony], [ "Máy lạnh", "Ban công" ], "Chìa ở quầy" ],
      body.values_at("name", "price", "room_type", "kind", "amenity_keys", "amenities", "note")
    assert_equal users(:owner).id.to_s, PaperTrail::Version.where(item_type: "Room").last.whodunnit

    as :owner, :post, api_v1_place_rooms_path(places(:tomo)), { room: { name: "Limdim", max_guests: 0 } }
    assert_response :unprocessable_entity
    assert_equal %w[max_guests name], body["errors"].keys.sort

    rooms(:limdim).bookings.create!(start_date: "2026-10-25", end_date: "2026-10-27", guests: 3)
    as :owner, :patch, api_v1_room_path(rooms(:limdim)), { room: { price: "550k", max_guests: 2 } }
    assert_response :success
    assert_equal 550_000, body["price"]
    assert_equal [ "1 đặt phòng sắp tới giữ giá cũ.", "Đặt phòng 25/10–27/10 có 3 khách, nhiều hơn tối đa 2." ], body["notices"]

    as :staff, :post, api_v1_place_rooms_path(places(:tomo)), { room: { name: "X", max_guests: 2 } }
    assert_response :forbidden
    as :staff, :patch, api_v1_room_path(rooms(:garden)), { room: { name: "X" } }
    assert_response :forbidden
    as :staff, :delete, api_v1_room_path(rooms(:garden))
    assert_response :forbidden
  end

  test "rooms: only a room that never had a booking can be deleted" do
    as :owner, :delete, api_v1_room_path(rooms(:limdim)) # the fixture booking
    assert_response :unprocessable_entity
    assert body.dig("errors", "base").present?

    as :owner, :delete, api_v1_room_path(rooms(:garden))
    assert_response :no_content
    assert_not Room.exists?(rooms(:garden).id)
  end

  test "services: owners manage the catalog, staff only list it" do
    as :owner, :post, api_v1_place_services_path(places(:tomo)), { service: { name: "Thuê xe máy", price: "150k", unit: "ngày" } }
    assert_response :created
    service = Service.find(body["id"])
    assert_equal [ "Thuê xe máy", 150_000, "ngày" ], body.values_at("name", "price", "unit")

    as :owner, :post, api_v1_place_services_path(places(:tomo)), { service: { name: "thuê xe máy", price: 1 } }
    assert_response :unprocessable_entity
    as :owner, :patch, api_v1_service_path(service), { service: { price: "120k" } }
    assert_equal 120_000, body["price"]

    as :staff, :patch, api_v1_service_path(service), { service: { price: 1 } }
    assert_response :forbidden
    as :staff, :delete, api_v1_service_path(service)
    assert_response :forbidden
    as :owner, :delete, api_v1_service_path(service)
    assert_response :no_content
  end

  test "homestay settings: bank for everyone, commissions owners only, 0–100" do
    as :owner, :patch, bank_api_v1_place_path(places(:tomo)), { place: { bank_name: "Vietcombank", bank_account: "0123456789", bank_holder: "NGUYEN THI LAN" } }
    assert_response :success
    assert_equal({ "name" => "Vietcombank", "account" => "0123456789", "holder" => "NGUYEN THI LAN" }, body["bank"])

    as :owner, :patch, commissions_api_v1_place_path(places(:tomo)), { place: { commissions: { airbnb: "15,5", booking: 18, agoda: "" } } }
    assert_response :success
    assert_equal({ "airbnb" => 15.5, "booking" => 18.0 }, body["commissions"])
    as :owner, :patch, commissions_api_v1_place_path(places(:tomo)), { place: { commissions: { airbnb: 120 } } }
    assert_response :unprocessable_entity
    assert body.dig("errors", "commissions").present?

    as :staff, :get, api_v1_place_path(places(:tomo))
    assert_response :success
    assert_equal [ "staff", "Vietcombank" ], [ body["role"], body.dig("bank", "name") ]
    assert_not body.key?("commissions")
    as :staff, :patch, bank_api_v1_place_path(places(:tomo)), { place: { bank_name: "X" } }
    assert_response :forbidden
    as :staff, :patch, commissions_api_v1_place_path(places(:tomo)), { place: { commissions: { airbnb: 1 } } }
    assert_response :forbidden
  end

  test "booking site: owners set it, open needs a room type shown and a bank for the deposit; staff 403, other homestay 404" do
    rooms(:limdim).update!(room_type: "double")
    as :owner, :patch, booking_site_api_v1_place_path(places(:tomo)), { booking_site: { open: true, deposit_percent: 30 } }
    assert_response :unprocessable_entity
    assert_equal [ "Nhận đặt phòng online cần tài khoản chuyển khoản để nhận cọc" ], body.dig("errors", "site_open")

    as :owner, :patch, booking_site_api_v1_place_path(places(:tomo)), { booking_site: { open: true, deposit_percent: 0, hold_minutes: 120, cutoff_hour: 22, hidden_room_types: [] } }
    assert_response :success
    assert_equal({ "open" => true, "deposit_percent" => 0, "hidden_room_types" => [], "hold_minutes" => 120, "cutoff_hour" => 22, "room_types" => [ "double" ] }, body["booking_site"])

    as :staff, :get, api_v1_place_path(places(:tomo))
    assert_not body.key?("booking_site")
    as :staff, :patch, booking_site_api_v1_place_path(places(:tomo)), { booking_site: { open: false } }
    assert_response :forbidden
    as :owner, :patch, booking_site_api_v1_place_path(places(:hiuhill)), { booking_site: { open: false } }
    assert_response :not_found
  end

  test "members: names and roles, owners first, no phones; staff too" do
    as :staff, :get, members_api_v1_place_path(places(:tomo))
    assert_response :success
    assert_equal [ { "id" => users(:owner).id, "name" => "Chị Lan", "role" => "owner" }, { "id" => @staff.id, "name" => "Bé Na", "role" => "staff" } ], body["members"]
    assert_no_match "0912345678", response.body
  end

  test "another owner's homestay, room and service are 404" do
    other_room = places(:hiuhill).rooms.create!(name: "Đồi", max_guests: 2)
    other_service = places(:hiuhill).services.create!(name: "Nước", price: 10_000)
    as :owner, :post, api_v1_place_rooms_path(places(:hiuhill)), { room: { name: "X", max_guests: 2 } }
    assert_response :not_found
    as :owner, :patch, api_v1_room_path(other_room), { room: { name: "X" } }
    assert_response :not_found
    as :owner, :delete, api_v1_service_path(other_service)
    assert_response :not_found
    as :owner, :get, members_api_v1_place_path(places(:hiuhill))
    assert_response :not_found
    as :owner, :get, api_v1_place_path(places(:hiuhill))
    assert_response :not_found
    as :owner, :patch, bank_api_v1_place_path(places(:hiuhill)), { place: { bank_name: "X" } }
    assert_response :not_found
  end
end
