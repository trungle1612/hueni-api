require "test_helper"

# Buồng phòng (#166).
class MiniApp::CleaningsControllerTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 10, 20, 10)
    @owner = users(:owner)
    @staff = User.create!(name: "Bé Na", phone_number: "0987654321", password: "password123")
    places(:tomo).place_memberships.create!(user: @staff, role: "staff")
    @tokens = { owner: @owner.api_tokens.create!.token, staff: @staff.api_tokens.create!.token }
    # Limdim: guest left this morning, the next one arrives today. Garden: guest in.
    rooms(:limdim).bookings.create!(start_date: "2026-10-18", end_date: "2026-10-20", checked_in_at: 2.days.ago).check_out
    rooms(:limdim).bookings.create!(start_date: "2026-10-20", end_date: "2026-10-21", guest_name: "Chị Hoa")
    rooms(:garden).update!(housekeeping: "clean")
    rooms(:garden).bookings.create!(start_date: "2026-10-19", end_date: "2026-10-22", checked_in_at: 1.day.ago)
  end

  def as(who, verb, path, params = {}) = send(verb, path, params:, headers: { "Authorization" => "Bearer #{@tokens.fetch(who)}" }, as: :json)
  def body = response.parsed_body

  test "list: checkout cleans (urgent when a guest arrives today) before daily tidies" do
    as :staff, :get, housekeeping_api_v1_place_path(places(:tomo))
    assert_response :success
    assert_equal 5, body["checklist"].size
    assert_equal [ [ "Limdim", "checkout", true, nil ], [ "Garden", "daily", false, nil ] ],
      body["rows"].map { it.values_at("room_name", "kind", "urgent", "task") }
  end

  test "assign, tick, start; finishing needs a person and every item, marks the room clean; undo the same day" do
    room = rooms(:limdim)
    as :staff, :post, finish_api_v1_room_cleaning_path(room)
    assert_response :unprocessable_entity
    assert_equal [ "Chọn người dọn trước" ], body.dig("errors", "base")

    as :staff, :patch, api_v1_room_cleaning_path(room), { cleaning: { assignee_id: @staff.id, checks: [ true, true, true, true, false ], start: true } }
    assert_response :success
    assert_equal [ @staff.id, "Bé Na" ], body["task"].values_at("assignee_id", "assignee_name")
    assert body.dig("task", "started_at")

    as :staff, :post, finish_api_v1_room_cleaning_path(room)
    assert_match "đủ 5 việc", body.dig("errors", "base").sole
    as :staff, :patch, api_v1_room_cleaning_path(room), { cleaning: { checks: [ true ] * 5 } }
    as :staff, :post, finish_api_v1_room_cleaning_path(room)
    assert_response :success
    assert body.dig("task", "done_at")
    assert room.reload.clean?
    assert_equal "Dọn xong", Activity.lines(PaperTrail::Version.where(item_type: "Room").order(:id).last(1)).sole.action

    as :staff, :post, undo_api_v1_room_cleaning_path(room)
    assert_response :success
    assert room.reload.dirty?
    assert_nil body.dig("task", "done_at")
    as :staff, :post, finish_api_v1_room_cleaning_path(room)
    assert room.reload.clean?
  end

  test "refusals: a room that needs no cleaning, an assignee from elsewhere, a bad checklist" do
    as :staff, :patch, api_v1_room_cleaning_path(rooms(:garden)), { cleaning: { start: true } }
    assert_equal [ "Phòng không cần dọn" ], body.dig("errors", "base")
    stranger = User.create!(name: "Người lạ", phone_number: "0911222333", password: "password123")
    as :staff, :patch, api_v1_room_cleaning_path(rooms(:limdim)), { cleaning: { assignee_id: stranger.id } }
    assert body.dig("errors", "assignee").present?
    as :staff, :patch, api_v1_room_cleaning_path(rooms(:limdim)), { cleaning: { checks: [ true ] } }
    assert body.dig("errors", "checks").present?
    as :staff, :post, undo_api_v1_room_cleaning_path(rooms(:limdim))
    assert_response :not_found
  end

  test "damage note: staff report it, shown on the room, logged; blank clears it" do
    as :staff, :patch, damage_api_v1_room_path(rooms(:garden)), { room: { damage_note: "Vòi sen rỉ nước" } }
    assert_response :success
    assert_equal "Vòi sen rỉ nước", body["damage_note"]
    as :staff, :get, rooms_api_v1_place_path(places(:tomo))
    assert_equal "Vòi sen rỉ nước", body["rooms"].find { it["id"] == rooms(:garden).id }["damage_note"]
    as :owner, :patch, damage_api_v1_room_path(rooms(:garden)), { room: { damage_note: "" } }
    lines = Activity.lines(PaperTrail::Version.where(item_type: "Room").order(:id).last(2))
    assert_equal [ [ "Báo hỏng / thiếu đồ", "Vòi sen rỉ nước" ], [ "Đã xử lý đồ hỏng", nil ] ], lines.map { [ it.action, it.detail ] }
  end

  test "another owner's homestay and rooms are 404" do
    room = places(:hiuhill).rooms.create!(name: "Đồi", max_guests: 2, housekeeping: "dirty")
    as :owner, :get, housekeeping_api_v1_place_path(places(:hiuhill))
    assert_response :not_found
    as :owner, :patch, api_v1_room_cleaning_path(room), { cleaning: { start: true } }
    assert_response :not_found
    as :owner, :post, finish_api_v1_room_cleaning_path(room)
    assert_response :not_found
    as :owner, :patch, damage_api_v1_room_path(room), { room: { damage_note: "X" } }
    assert_response :not_found
  end
end
