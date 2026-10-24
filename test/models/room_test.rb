require "test_helper"

class RoomTest < ActiveSupport::TestCase
  test "active by default" do
    assert Room.new.active?
  end

  test "requires name and positive max_guests" do
    room = Room.new(place: places(:tomo), max_guests: 0)
    assert_not room.valid?
    assert_includes room.errors.attribute_names, :name
    assert_includes room.errors.attribute_names, :max_guests
  end

  test "price is optional whole VND amount, not negative" do
    room = rooms(:garden)
    assert room.tap { it.price = nil }.valid?
    assert room.tap { it.price = 450_000 }.valid?
    assert_not room.tap { it.price = -1 }.valid?
    assert_not room.tap { it.price = 1.5 }.valid?
  end

  test "photo_urls defaults to empty array" do
    assert_equal [], Room.new.photo_urls
  end

  test "photo_urls round-trips an array of http(s) urls" do
    urls = [ "https://hueni.me/images/homestay/tomo-homestay/limdim-1.webp", "http://example.com/a.jpg" ]
    rooms(:garden).update!(photo_urls: urls)
    assert_equal urls, rooms(:garden).reload.photo_urls
  end

  test "photo_urls rejects non-array and non-http entries" do
    room = rooms(:garden)
    assert_not room.tap { it.photo_urls = "https://example.com/a.jpg" }.valid?
    assert_not room.tap { it.photo_urls = [ "javascript:alert(1)" ] }.valid?
    assert_not room.tap { it.photo_urls = [ 42 ] }.valid?
  end

  test "name is unique within a place" do
    assert_not Room.new(place: places(:tomo), name: "Limdim", max_guests: 2).valid?
    assert Room.new(place: places(:hiuhill), name: "Limdim", max_guests: 2).valid?
  end

  test "db enforces unique name per place" do
    assert_raises(ActiveRecord::RecordNotUnique) do
      Room.new(place: places(:tomo), name: "Limdim", max_guests: 2).save(validate: false)
    end
  end

  test "db enforces place foreign key" do
    assert_raises(ActiveRecord::InvalidForeignKey) do
      Room.new(place_id: 0, name: "Ghost", max_guests: 2).save(validate: false)
    end
  end

  test "price accepts Vietnamese-formatted input" do
    { "450.000" => 450_000, "450,000" => 450_000, "450 000 ₫" => 450_000, "450000" => 450_000, "" => nil, 450_000 => 450_000,
      "450k" => 450_000, "450 K" => 450_000, "450 nghìn" => 450_000, "1,2tr" => 1_200_000, "1.5 triệu" => 1_500_000 }.each do |input, expected|
      price = Room.new(price: input).price
      expected.nil? ? assert_nil(price, "input #{input.inspect}") : assert_equal(expected, price, "input #{input.inspect}")
    end
  end

  test "validation messages use Vietnamese attribute names" do
    room = Room.new(place: places(:tomo), name: "", max_guests: 0)
    room.valid?
    assert_includes room.errors.full_messages, "Tên phòng không thể để trống"
    assert room.errors.full_messages.any? { it.start_with?("Số khách tối đa") }
  end

  test "price typos are rejected instead of silently saving a wrong number" do
    [ "450kk", "-100", "abc", "1e6", "k" ].each do |input|
      room = rooms(:garden)
      room.price = input
      assert_not room.valid?, "input #{input.inspect} should be invalid"
      assert_includes room.errors.attribute_names, :price
    end
  end

  test "rooms start clean and only take clean or dirty" do
    room = rooms(:garden)
    assert room.clean?
    room.dirty!
    assert room.reload.dirty?
    assert_raises(ActiveRecord::StatementInvalid) { room.update_column(:housekeeping, "cleaning") }
  end

  test "Bảo trì needs a reason and a last day from today; ending it clears both" do
    travel_to Time.zone.local(2026, 10, 5, 12)
    room = rooms(:garden)
    assert_not room.update(housekeeping: "maintenance")
    assert_equal %i[maintenance_reason maintenance_until], room.errors.attribute_names.sort
    assert_not room.update(housekeeping: "maintenance", maintenance_reason: "Hỏng máy lạnh", maintenance_until: "2026-10-04")
    assert_includes room.errors[:maintenance_until], "không được trước hôm nay"

    assert room.update(housekeeping: "maintenance", maintenance_reason: " Hỏng máy lạnh ", maintenance_until: "2026-10-07")
    assert_equal "Hỏng máy lạnh", room.maintenance_reason
    assert [ room.maintenance_on?(Date.new(2026, 10, 5)), room.maintenance_on?(Date.new(2026, 10, 7)) ].all?
    assert_not room.maintenance_on?(Date.new(2026, 10, 8))

    room.clean!
    assert_equal [ nil, nil ], room.reload.values_at(:maintenance_reason, :maintenance_until)
  end

  test "Bảo trì is refused while a guest is in the room" do
    travel_to Time.zone.local(2026, 10, 1, 15)
    bookings(:limdim_confirmed).check_in(guests: 2)
    assert_not rooms(:limdim).update(housekeeping: "maintenance", maintenance_reason: "Sơn lại", maintenance_until: "2026-10-05")
    assert_includes rooms(:limdim).errors[:base], "Phòng đang có khách. Đổi tình trạng được sau khi trả phòng."
  end

  test "end_maintenance: past its last day the room needs cleaning" do
    travel_to Time.zone.local(2026, 10, 5, 12)
    rooms(:garden).update!(housekeeping: "maintenance", maintenance_reason: "Sơn lại", maintenance_until: "2026-10-05")
    Room.end_maintenance
    assert rooms(:garden).reload.maintenance?

    travel_to Time.zone.local(2026, 10, 6, 0, 5)
    Room.end_maintenance
    assert rooms(:garden).reload.dirty?
    assert_nil rooms(:garden).maintenance_until
  end
end
