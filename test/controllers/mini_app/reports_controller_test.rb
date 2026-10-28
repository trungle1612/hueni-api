require "test_helper"

# Mini App report and search (#155).
class MiniApp::ReportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 10, 20, 10)
    rooms(:limdim).update!(price: 500_000)
    @stay = rooms(:limdim).bookings.create!(start_date: "2026-10-18", end_date: "2026-10-20", guest_name: "Nguyễn Thị Hoa", guest_phone: "0905 123 456", checked_in_at: 2.days.ago, checked_out_at: 1.hour.ago)
    @stay.payments.create!(amount: 400_000, payment_method: "cash")
    @coming = rooms(:garden).bookings.create!(start_date: "2026-10-25", end_date: "2026-10-26", guest_name: "Anh Hoà")
    @staff = User.create!(name: "Bé Na", phone_number: "0987654321", password: "password123")
    places(:tomo).place_memberships.create!(user: @staff, role: "staff")
    @tokens = { owner: users(:owner).api_tokens.create!.token, staff: @staff.api_tokens.create!.token }
  end

  def as(who, verb, path, params = {}) = send(verb, path, params:, headers: { "Authorization" => "Bearer #{@tokens.fetch(who)}" }, as: (:json unless verb == :get))
  def body = response.parsed_body

  test "report: the month in numbers for owners, with Công nợ and the period before" do
    as :owner, :get, report_api_v1_place_path(places(:tomo))
    assert_response :success
    assert_equal [ "2026-10", "2026-10-01", "2026-10-31", "2026-10-20", true ], body.values_at("period", "first", "finish", "last", "current")
    assert_equal [ 2_000_000, 4, 500_000, 1_600_000 ], body.values_at("revenue", "sold", "adr", "due") # + the fixture stay 01–03/10
    assert_equal [ { "key" => "manual", "label" => "Trực tiếp", "nights" => 4, "bookings" => 2, "revenue" => 2_000_000, "commission" => nil, "net" => 2_000_000 } ], body["channels"]
    assert_equal [ "Limdim", 4, 2_000_000 ], body["top_rooms"].first.values_at("name", "sold", "revenue")
    assert_equal [ bookings(:limdim_confirmed).id, @stay.id ], body["debts"].pluck("id")
    debt = body["debts"].last
    assert_equal [ @stay.id, 600_000, true, 500_000 ], debt.values_at("id", "due", "overdue", "price")
    assert_equal [ "2026-09-01", "2026-09-20", 0 ], body["previous"].values_at("first", "last", "revenue")

    as :owner, :get, report_api_v1_place_path(places(:tomo), period: "7d")
    assert_equal [ "7d", "2026-10-14", "2026-10-20" ], body.values_at("period", "first", "last")

    as :owner, :get, report_api_v1_place_path(places(:tomo), month: "2026-12")
    assert_equal [ true, false ], [ body["future"], body.key?("previous") ]
  end

  test "report.csv is the Xuất CSV file" do
    as :owner, :get, report_api_v1_place_path(places(:tomo), format: :csv)
    assert_response :success
    assert_equal "text/csv; charset=utf-8", response.media_type + "; charset=utf-8"
    assert_match "bao-cao-tomo-homestay-2026-10-01-2026-10-20.csv", response.headers["Content-Disposition"]
    assert_match "\"Nguyễn Thị Hoa\"", response.body
  end

  test "report: staff 403, another owner's homestay 404" do
    as :staff, :get, report_api_v1_place_path(places(:tomo))
    assert_response :forbidden
    as :staff, :get, report_api_v1_place_path(places(:tomo), format: :csv)
    assert_response :forbidden
    as :owner, :get, report_api_v1_place_path(places(:hiuhill))
    assert_response :not_found
  end

  test "search: by name without diacritics, phone digits or code, in sections; staff too, no prices" do
    as :staff, :post, search_api_v1_place_path(places(:tomo)), { q: "hoa" }
    assert_response :success
    assert_equal [ [], [ @coming.id ], [ @stay.id ] ], body.values_at("in_house", "upcoming", "past").map { it.pluck("id") }
    assert_not body["past"].sole.key?("price")

    as :staff, :post, search_api_v1_place_path(places(:tomo)), { q: "0905123" }
    assert_equal [ @stay.id ], body["past"].pluck("id")
    as :staff, :post, search_api_v1_place_path(places(:tomo)), { q: @coming.code }
    assert_equal [ @coming.id ], body["upcoming"].pluck("id")
    as :staff, :post, search_api_v1_place_path(places(:tomo)), { q: " " }
    assert_equal({ "in_house" => [], "upcoming" => [], "past" => [] }, body)
  end

  test "search: only this homestay; another owner's homestay 404" do
    other = places(:hiuhill).rooms.create!(name: "Đồi", max_guests: 2)
    other.bookings.create!(start_date: "2026-10-20", end_date: "2026-10-21", guest_name: "Hoa")
    as :owner, :post, search_api_v1_place_path(places(:tomo)), { q: "hoa" }
    assert_equal 2, body.values.flatten.size
    as :owner, :post, search_api_v1_place_path(places(:hiuhill)), { q: "hoa" }
    assert_response :not_found
  end
end
