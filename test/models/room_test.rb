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
    { "450.000" => 450_000, "450,000" => 450_000, "450 000 ₫" => 450_000, "450000" => 450_000, "" => nil, 450_000 => 450_000 }.each do |input, expected|
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
    [ "450k", "-100", "abc", "1e6" ].each do |input|
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
end
