require "test_helper"

class GroupTest < ActiveSupport::TestCase
  setup do
    travel_to Time.zone.local(2026, 10, 20, 10)
    rooms(:limdim).update!(price: 500_000)
    rooms(:garden).update!(price: 300_000)
    @attic = places(:tomo).rooms.create!(name: "Attic", max_guests: 2, price: 400_000)
    @group = places(:tomo).groups.build(name: "Đoàn Sao Mai", contact: "Anh Minh", phone: "0901234567", discount_pct: 10)
  end

  def book(rooms) = @group.book(rooms, start_date: Date.new(2026, 10, 20), end_date: Date.new(2026, 10, 22))

  test "book: one booking per room at the group price, numbered DOAN per homestay" do
    assert book([ rooms(:limdim), rooms(:garden) ])
    assert_equal "DOAN-0001", @group.code
    garden, limdim = @group.rooms_booked # by room name
    assert_equal [ 100_000, "Giá đoàn DOAN-0001" ], limdim.values_at(:discount, :discount_reason)
    assert_equal [ 900_000, 540_000 ], [ limdim.total, garden.total ]
    assert_equal [ "Đoàn Sao Mai", 4 ], limdim.values_at(:guest_name, :guests)
    assert_equal "DOAN-0002", places(:tomo).groups.create!(name: "B").code
  end

  test "book is all or nothing: a clash names the room and keeps nothing" do
    rooms(:garden).bookings.create!(start_date: "2026-10-21", end_date: "2026-10-23", guest_name: "Chị Hoa")
    assert_no_difference -> { Group.count } do
      assert_no_difference(-> { Booking.count }) { assert_not book([ rooms(:limdim), rooms(:garden) ]) }
    end
    assert_match(/\APhòng Garden: Trùng lịch đêm 21\/10 với Chị Hoa/, @group.errors[:base].sole)

    assert_not @group.book([ rooms(:limdim) ], start_date: Date.new(2026, 10, 20), end_date: Date.new(2026, 10, 22))
    assert_match "ít nhất 2 phòng", @group.errors[:base].last
  end

  test "check_in_all checks in every room or none" do
    book([ rooms(:limdim), rooms(:garden) ])
    rooms(:garden).bookings.create!(start_date: "2026-10-18", end_date: "2026-10-20", checked_in_at: 2.days.ago)
    assert_not @group.check_in_all
    assert_match "Phòng Garden: Phòng đang có khách", @group.errors[:base].sole
    assert @group.bookings.reload.none?(&:checked_in_at)

    rooms(:garden).bookings.in_house.sole.check_out
    assert @group.reload.check_in_all
    assert @group.bookings.reload.all?(&:checked_in_at)
  end

  test "pay fills each billed room's due in room order; Khách tự trả and over-paying are left out" do
    book([ rooms(:limdim), rooms(:garden), @attic ])
    attic = @group.bookings.find_by!(room: @attic)
    attic.update!(pays_own: true)
    assert_equal [ 1_440_000 ], [ @group.billed.sum(&:due) ] # Garden 540k + Limdim 900k

    assert @group.pay("600k", payment_method: "bank")
    assert_equal({ "Garden" => 540_000, "Limdim" => 60_000, "Attic" => 0 }, @group.bookings.reload.to_h { [ it.room.name, it.paid ] })
    assert_equal "Thu theo đoàn DOAN-0001", Payment.last.note

    assert_not @group.pay(900_000, payment_method: "cash")
    assert_match "840.000 ₫", @group.errors[:base].sole

    @group.update!(bill: "split")
    assert_includes @group.billed, attic
  end

  test "Hoạt động words the group and Khách tự trả" do
    book([ rooms(:limdim), rooms(:garden) ])
    @group.update!(bill: "split", contact: "Chị Ngọc")
    @group.bookings.first.update!(pays_own: true)
    lines = Activity.lines(PaperTrail::Version.where(place_id: places(:tomo).id).order(:id).to_a)
    assert_equal [ "Tạo đoàn", "DOAN-0001 Đoàn Sao Mai" ], lines.find { it.action == "Tạo đoàn" }.to_h.values_at(:action, :detail)
    assert_equal "DOAN-0001 Đoàn Sao Mai: trưởng đoàn: Anh Minh → Chị Ngọc, tách hoá đơn theo phòng", lines.find { it.action == "Sửa đoàn" }.detail
    assert_equal "Đoàn Sao Mai: khách tự trả", lines.last.detail
  end
end
