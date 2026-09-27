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
end
