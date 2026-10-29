require "test_helper"

# Hồ sơ khách (#165).
class MiniApp::GuestsControllerTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 10, 20, 10)
    rooms(:limdim).update!(price: 500_000)
    rooms(:garden).update!(price: 300_000)
    @first = rooms(:limdim).bookings.create!(start_date: "2026-08-01", end_date: "2026-08-03", guest_name: "Nguyễn Thị Hoa", guest_phone: "+84 912 000 111")
    @first.payments.create!(amount: 1_000_000, payment_method: "cash")
    @latest = rooms(:garden).bookings.create!(start_date: "2026-10-20", end_date: "2026-10-21", guest_name: "Chị Hoa", guest_phone: "0912 000 111")
    @other = rooms(:garden).bookings.create!(start_date: "2026-10-25", end_date: "2026-10-26", guest_name: "Anh Tuấn")
    @owner = users(:owner)
    @staff = User.create!(name: "Bé Na", phone_number: "0987654321", password: "password123")
    places(:tomo).place_memberships.create!(user: @staff, role: "staff")
    @tokens = { owner: @owner.api_tokens.create!.token, staff: @staff.api_tokens.create!.token }
  end

  def as(who, verb, path, params = {}) = send(verb, path, params:, headers: { "Authorization" => "Bearer #{@tokens.fetch(who)}" }, as: :json)
  def body = response.parsed_body

  test "list: one guest per phone (else name), newest stay first, searched by name without diacritics or phone" do
    as :staff, :post, guests_api_v1_place_path(places(:tomo))
    assert_response :success
    assert_equal [ [ @other.id, "Anh Tuấn", 1, false ], [ @latest.id, "Chị Hoa", 2, true ] ],
      body["guests"].first(2).map { it.values_at("booking_id", "name", "visits", "returning") }
    assert_equal "2026-08-01", body["guests"].second["first_stay"]

    as :staff, :post, guests_api_v1_place_path(places(:tomo)), { q: "nguyen thi" }
    assert_equal [ @latest.id ], body["guests"].pluck("booking_id")
    as :staff, :post, guests_api_v1_place_path(places(:tomo)), { q: "000111" }
    assert_equal [ @latest.id ], body["guests"].pluck("booking_id")
  end

  test "profile: stays, money, note; staff flag a guest and see it on every booking; flagging is logged" do
    as :staff, :get, api_v1_booking_guest_path(@first)
    assert_response :success
    assert_equal [ "Chị Hoa", 2, 1_000_000, 300_000 ], body.values_at("name", "visits", "paid", "due")
    assert_equal [ @latest.id, @first.id ], body["bookings"].pluck("id")

    as :staff, :patch, api_v1_booking_guest_path(@latest), { guest: { note: "Thích tầng 1", flag: "Hay trả phòng muộn" } }
    assert_response :success
    assert_equal [ "Thích tầng 1", "Hay trả phòng muộn" ], body.values_at("note", "flag")
    as :staff, :get, api_v1_booking_path(@first)
    assert_equal "Hay trả phòng muộn", body["guest_flag"]

    as :staff, :patch, api_v1_booking_guest_path(@latest), { guest: { note: "Thích tầng 2" } }
    as :owner, :patch, api_v1_booking_guest_path(@latest), { guest: { flag: "" } }
    versions = PaperTrail::Version.where(item_type: "Guest").order(:id)
    assert_equal [ @staff.id.to_s, @owner.id.to_s ], versions.map(&:whodunnit)
    lines = Activity.lines(versions)
    assert_equal [ [ "Đánh dấu khách cần lưu ý", "Chị Hoa · Hay trả phòng muộn" ], [ "Bỏ đánh dấu khách", "Chị Hoa" ] ], lines.map { [ it.action, it.detail ] }
    assert versions.none? { it.object_changes.to_s.include?("000111") }
  end

  test "OTA bookings have no profile; another owner's homestay and bookings are 404" do
    feed = rooms(:garden).calendar_feeds.create!(provider: "airbnb", url: "https://1.1.1.1/a.ics")
    ota = rooms(:garden).bookings.create!(start_date: "2026-11-01", end_date: "2026-11-02", source: "ical", calendar_feed: feed, uid: "x")
    as :owner, :get, api_v1_booking_guest_path(ota)
    assert_response :not_found

    room = places(:hiuhill).rooms.create!(name: "Đồi", max_guests: 2)
    other = room.bookings.create!(start_date: "2026-10-20", end_date: "2026-10-21", guest_name: "Khác")
    as :owner, :post, guests_api_v1_place_path(places(:hiuhill))
    assert_response :not_found
    as :owner, :get, api_v1_booking_guest_path(other)
    assert_response :not_found
    as :owner, :patch, api_v1_booking_guest_path(other), { guest: { flag: "X" } }
    assert_response :not_found
  end
end
