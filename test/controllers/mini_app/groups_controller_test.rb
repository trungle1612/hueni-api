require "test_helper"

# Đặt phòng theo đoàn (#164).
class MiniApp::GroupsControllerTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 10, 20, 10)
    rooms(:limdim).update!(price: 500_000)
    rooms(:garden).update!(price: 300_000)
    @attic = places(:tomo).rooms.create!(name: "Attic", max_guests: 2, price: 400_000)
    @owner = users(:owner)
    @staff = User.create!(name: "Bé Na", phone_number: "0987654321", password: "password123")
    places(:tomo).place_memberships.create!(user: @staff, role: "staff")
    @tokens = { owner: @owner.api_tokens.create!.token, staff: @staff.api_tokens.create!.token }
  end

  def as(who, verb, path, params = {}) = send(verb, path, params:, headers: { "Authorization" => "Bearer #{@tokens.fetch(who)}" }, as: :json)
  def body = response.parsed_body

  def create_group(who = :owner, room_ids: [ rooms(:limdim).id, rooms(:garden).id ], discount_pct: 10)
    as who, :post, api_v1_place_groups_path(places(:tomo)),
      { group: { name: "Đoàn Sao Mai", contact: "Anh Minh", phone: "0901234567", origin: "Công ty lữ hành", discount_pct: }, room_ids:, start_date: "2026-10-20", end_date: "2026-10-22" }
    Group.last
  end

  test "create: rooms at the group price, all or nothing; staff can't set the discount" do
    group = create_group
    assert_response :created
    assert_equal [ "DOAN-0001", 10, "one", 1_440_000, 0, 1_440_000 ], body.values_at("code", "discount_pct", "bill", "total", "paid", "due")
    assert_equal [ "Garden", "Limdim" ], body["bookings"].map { Room.find(it["room_id"]).name }
    assert_equal [ group.id ] * 2, body["bookings"].pluck("group_id")
    assert_equal @owner.id.to_s, PaperTrail::Version.where(item_type: "Group").last.whodunnit

    create_group(:staff, room_ids: [ @attic.id, rooms(:limdim).id ])
    assert_response :unprocessable_entity
    assert_match(/\APhòng Limdim: Trùng lịch/, body.dig("errors", "base").sole)
    assert_equal 1, Group.count

    create_group(:staff, room_ids: [ @attic.id, places(:tomo).rooms.create!(name: "Mái", max_guests: 2, price: 100_000).id ])
    assert_response :created
    assert_equal [ 0, nil ], [ body["discount_pct"], body["bookings"].first["price"] ]
  end

  test "rooms: add, change room, Khách tự trả, Bỏ khỏi đoàn via the booking" do
    group = create_group
    as :staff, :post, api_v1_group_bookings_path(group), { room_id: @attic.id, start_date: "2026-10-20", end_date: "2026-10-21" }
    assert_response :created
    assert_equal 3, body["bookings"].size

    attic = group.bookings.find_by!(room: @attic)
    as :staff, :patch, api_v1_group_booking_path(group, attic), { booking: { room_id: rooms(:garden).id } }
    assert_response :unprocessable_entity
    assert_match "Trùng lịch", body.dig("errors", "base").sole

    as :staff, :patch, api_v1_group_booking_path(group, attic), { booking: { pays_own: true } }
    assert_response :success
    assert_equal 1_440_000, body["total"]

    as :staff, :patch, api_v1_booking_path(group.bookings.find_by!(room: rooms(:garden))), { booking: { status: "cancelled", cancel_reason: "Bỏ khỏi đoàn" } }
    as :staff, :get, api_v1_group_path(group)
    assert_equal [ "Attic", "Limdim" ], body["bookings"].map { Room.find(it["room_id"]).name }
    as :staff, :patch, api_v1_group_booking_path(group, attic), { booking: { room_id: rooms(:garden).id } }
    assert_response :success
    assert_equal rooms(:garden), attic.reload.room
  end

  test "check in the whole group, take one payment for it, switch to split bills" do
    group = create_group
    as :staff, :post, check_in_api_v1_group_path(group)
    assert_response :success
    assert body["bookings"].all? { it["checked_in_at"] }

    as :staff, :post, payments_api_v1_group_path(group), { payment: { amount: "600k", payment_method: "cash" } }
    assert_response :success
    assert_equal [ 600_000, 840_000 ], body.values_at("paid", "due")
    assert_equal [ 540_000, 60_000 ], body["bookings"].map { it["paid"] }

    as :staff, :post, payments_api_v1_group_path(group), { payment: { amount: 2_000_000, payment_method: "cash" } }
    assert_response :unprocessable_entity
    as :staff, :patch, api_v1_group_path(group), { group: { bill: "split", discount_pct: 50 } }
    assert_equal [ "split", 10 ], body.values_at("bill", "discount_pct")
  end

  test "another owner's homestay and group are 404" do
    room = places(:hiuhill).rooms.create!(name: "Đồi", max_guests: 2)
    other = places(:hiuhill).groups.create!(name: "Khác")
    as :owner, :post, api_v1_place_groups_path(places(:hiuhill)), { group: { name: "X" }, room_ids: [ room.id ], start_date: "2026-10-20", end_date: "2026-10-21" }
    assert_response :not_found
    create_group(room_ids: [ rooms(:limdim).id, room.id ])
    assert_response :not_found
    as :owner, :get, api_v1_group_path(other)
    assert_response :not_found
    as :owner, :post, check_in_api_v1_group_path(other)
    assert_response :not_found
    group = create_group
    as :owner, :post, api_v1_group_bookings_path(group), { room_id: room.id, start_date: "2026-10-23", end_date: "2026-10-24" }
    assert_response :not_found
    as :owner, :patch, api_v1_group_booking_path(group, room.bookings.create!(start_date: "2026-10-25", end_date: "2026-10-26")), { booking: { pays_own: true } }
    assert_response :not_found
  end
end
