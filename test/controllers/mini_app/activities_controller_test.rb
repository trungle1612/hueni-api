require "test_helper"

# Mini App Hoạt động and Lịch sử (#158): the admin's activity lines as JSON, owners only.
class MiniApp::ActivitiesControllerTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 10, 20, 10)
    rooms(:limdim).update!(price: 500_000)
    @owner = users(:owner)
    @staff = User.create!(name: "Bé Na", phone_number: "0987654321", password: "password123")
    places(:tomo).place_memberships.create!(user: @staff, role: "staff")
    @tokens = { owner: @owner.api_tokens.create!.token, staff: @staff.api_tokens.create!.token }
    PaperTrail.request(whodunnit: @owner.id.to_s) do
      @booking = rooms(:limdim).bookings.create!(start_date: "2026-10-20", end_date: "2026-10-22", guest_name: "Chị Hoa")
      @booking.payments.create!(amount: 300_000, payment_method: "bank")
      rooms(:garden).dirty!
      rooms(:garden).clean!
    end
  end

  def as(who, path) = get(path, headers: { "Authorization" => "Bearer #{@tokens.fetch(who)}" })
  def body = response.parsed_body

  test "Hoạt động: the homestay's lines, newest first, worded like /admin" do
    as :owner, activity_api_v1_place_path(places(:tomo))
    assert_response :success
    lines = body["activities"]
    assert_equal [ "Dọn xong", "Thu tiền", "Đặt phòng", "Sửa phòng" ], lines.pluck("action")
    assert_equal [ "Hệ thống", "giá chưa có → 500.000 ₫" ], lines.last.values_at("actor", "detail") # the setup's price, no user
    assert_equal({ "kind" => "clean", "actor" => "Chị Lan", "room_name" => "Garden", "detail" => nil }, lines.first.slice("kind", "actor", "room_name", "detail"))
    assert_equal "300.000 ₫ · Chuyển khoản · #{@booking.code}", lines.second["detail"]
    assert_equal [ "booking", "Chị Hoa 20/10–22/10", "Limdim", "2026-10-20T10:00:00.000+07:00" ], lines.third.values_at("kind", "detail", "room_name", "at")
    assert_nil body["next_before"]
  end

  test "Hoạt động pages 50 at a time with before" do
    PaperTrail.request(whodunnit: @owner.id.to_s) { 50.times { rooms(:garden).update!(max_guests: it + 3) } }
    as :owner, activity_api_v1_place_path(places(:tomo))
    assert_equal 50, body["activities"].size
    next_before = body["next_before"]
    assert_equal body["activities"].last["id"], next_before

    as :owner, activity_api_v1_place_path(places(:tomo), before: next_before)
    assert_equal [ "Dọn xong", "Thu tiền", "Đặt phòng", "Sửa phòng" ], body["activities"].pluck("action")
    assert_nil body["next_before"]

    as :owner, activity_api_v1_place_path(places(:tomo), before: "x")
    assert_equal 50, body["activities"].size # a bad cursor = the first page
  end

  test "Lịch sử: only this booking, its payments included" do
    rooms(:limdim).bookings.create!(start_date: "2026-10-25", end_date: "2026-10-26", guest_name: "Khác")
    as :owner, history_api_v1_booking_path(@booking)
    assert_response :success
    assert_equal [ "Thu tiền", "Đặt phòng" ], body["activities"].pluck("action")
  end

  test "staff 403, another owner's homestay and booking 404" do
    as :staff, activity_api_v1_place_path(places(:tomo))
    assert_response :forbidden
    as :staff, history_api_v1_booking_path(@booking)
    assert_response :forbidden

    other = places(:hiuhill).rooms.create!(name: "Đồi", max_guests: 2).bookings.create!(start_date: "2026-10-20", end_date: "2026-10-21")
    as :owner, activity_api_v1_place_path(places(:hiuhill))
    assert_response :not_found
    as :owner, history_api_v1_booking_path(other)
    assert_response :not_found
  end
end
