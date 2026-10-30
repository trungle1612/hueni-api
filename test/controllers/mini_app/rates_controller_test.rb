require "test_helper"

# Mini App Loại phòng và giá (#163): seasons, Phụ thu, Ở dài ngày, Chính sách huỷ. Owners write; staff see Phụ thu and the policy.
class MiniApp::RatesControllerTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 10, 20, 10)
    rooms(:limdim).update!(price: 500_000)
    @staff = User.create!(name: "Bé Na", phone_number: "0987654321", password: "password123")
    places(:tomo).place_memberships.create!(user: @staff, role: "staff")
    @tokens = { owner: users(:owner).api_tokens.create!.token, staff: @staff.api_tokens.create!.token }
  end

  def as(who, verb, path, params = {}) = send(verb, path, params:, headers: { "Authorization" => "Bearer #{@tokens.fetch(who)}" }, as: (:json unless verb == :get))
  def body = response.parsed_body

  test "seasons: owners add, list, edit and delete; new bookings price them; staff 403" do
    as :owner, :post, api_v1_place_seasons_path(places(:tomo)), { season: { name: "Lễ 20/11", from: "2026-11-19", to: "2026-11-20", pct: 30 } }
    assert_response :created
    season = Season.find(body["id"])
    assert_equal [ "Lễ 20/11", "2026-11-19", "2026-11-20", 30 ], body.values_at("name", "from", "to", "pct")
    assert_equal [ users(:owner).id.to_s, "Thêm mùa" ], [ season.versions.last.whodunnit, Activity.entry(season.versions.last)[:action] ]

    as :owner, :post, api_v1_place_seasons_path(places(:tomo)), { season: { name: "Sai", from: "2026-11-20", to: "2026-11-19", pct: 10 } }
    assert_response :unprocessable_entity
    assert_equal [ "Đến ngày phải từ ngày bắt đầu trở đi" ], body.dig("errors", "to")

    as :owner, :post, api_v1_place_bookings_path(places(:tomo)), { booking: { room_id: rooms(:limdim).id, start_date: "2026-11-18", end_date: "2026-11-20", guest_name: "Chị Mai" } }
    assert_response :created
    assert_equal 1_150_000, body["room_total"]

    as :owner, :patch, api_v1_season_path(season), { season: { pct: 40 } }
    assert_equal 40, body["pct"]
    as :owner, :get, seasons_api_v1_place_path(places(:tomo))
    assert_equal [ season.id ], body["seasons"].pluck("id")

    as :staff, :get, seasons_api_v1_place_path(places(:tomo))
    assert_response :forbidden
    as :staff, :post, api_v1_place_seasons_path(places(:tomo)), { season: { name: "X", from: "2026-11-01", to: "2026-11-02", pct: 1 } }
    assert_response :forbidden
    as :staff, :patch, api_v1_season_path(season), { season: { pct: 1 } }
    assert_response :forbidden
    as :staff, :delete, api_v1_season_path(season)
    assert_response :forbidden
    as :owner, :delete, api_v1_season_path(season)
    assert_response :no_content
  end

  test "surcharges: owners manage the list, staff only read it" do
    as :staff, :get, surcharges_api_v1_place_path(places(:tomo))
    assert_response :success
    assert_equal [], body["surcharges"]

    as :owner, :post, api_v1_place_surcharges_path(places(:tomo)), { surcharge: { name: "Người lớn thêm", price: "150k", unit: "đêm" } }
    assert_response :created
    surcharge = Surcharge.find(body["id"])
    assert_equal [ "Người lớn thêm", 150_000, "đêm" ], body.values_at("name", "price", "unit")
    as :owner, :post, api_v1_place_surcharges_path(places(:tomo)), { surcharge: { name: "người lớn thêm", price: 1 } }
    assert_response :unprocessable_entity
    as :owner, :patch, api_v1_surcharge_path(surcharge), { surcharge: { price: 0 } }
    assert_equal 0, body["price"]

    as :staff, :patch, api_v1_surcharge_path(surcharge), { surcharge: { price: 1 } }
    assert_response :forbidden
    as :staff, :delete, api_v1_surcharge_path(surcharge)
    assert_response :forbidden
    as :owner, :delete, api_v1_surcharge_path(surcharge)
    assert_response :no_content
  end

  test "rules: owners set Ở dài ngày and Chính sách huỷ, everyone sees them" do
    as :owner, :patch, rules_api_v1_place_path(places(:tomo)), { place: { long_stay: true, cancel_policy: "mid" } }
    assert_response :success
    assert_equal [ true, "mid", "Vừa phải" ], [ body["long_stay"], body.dig("cancel_policy", "key"), body.dig("cancel_policy", "label") ]
    as :owner, :patch, rules_api_v1_place_path(places(:tomo)), { place: { cancel_policy: "lax" } }
    assert_response :unprocessable_entity
    assert body.dig("errors", "cancel_policy").present?

    as :staff, :get, api_v1_place_path(places(:tomo))
    assert_equal [ true, "mid" ], [ body["long_stay"], body.dig("cancel_policy", "key") ]
    as :staff, :patch, rules_api_v1_place_path(places(:tomo)), { place: { long_stay: false } }
    assert_response :forbidden
  end

  test "another owner's homestay, season and surcharge are 404" do
    other_season = places(:hiuhill).seasons.create!(name: "Tết", from: "2026-11-01", to: "2026-11-02", pct: 10)
    other_surcharge = places(:hiuhill).surcharges.create!(name: "Trẻ em", price: 50_000)
    as :owner, :get, seasons_api_v1_place_path(places(:hiuhill))
    assert_response :not_found
    as :owner, :get, surcharges_api_v1_place_path(places(:hiuhill))
    assert_response :not_found
    as :owner, :post, api_v1_place_seasons_path(places(:hiuhill)), { season: { name: "X", from: "2026-11-01", to: "2026-11-02", pct: 1 } }
    assert_response :not_found
    as :owner, :patch, api_v1_season_path(other_season), { season: { pct: 1 } }
    assert_response :not_found
    as :owner, :delete, api_v1_surcharge_path(other_surcharge)
    assert_response :not_found
    as :owner, :patch, rules_api_v1_place_path(places(:hiuhill)), { place: { long_stay: true } }
    assert_response :not_found
  end
end
