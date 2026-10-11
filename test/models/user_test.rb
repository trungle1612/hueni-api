require "test_helper"

class UserTest < ActiveSupport::TestCase
  def build(**attrs)
    User.new(phone_number: "0987654321", name: "Chị Mai", password: "password123", **attrs)
  end

  test "valid with defaults; role defaults to user" do
    user = build
    assert user.valid?
    assert user.user?
  end

  test "requires name and phone number" do
    user = build(name: "", phone_number: "")
    assert_not user.valid?
    assert_includes user.errors.attribute_names, :name
    assert_includes user.errors.attribute_names, :phone_number
  end

  test "normalizes phone numbers to 10 digits starting with 0, unique" do
    [ "0987654321", "0987 654 321", "0987.654.321", "+84 987 654 321", "84987654321", " 098-765-4321 " ].each do |input|
      assert_equal "0987654321", build(phone_number: input).phone_number, input
    end
    assert_not build(phone_number: "+84 912 345 678").valid? # users(:owner)
  end

  test "rejects phone numbers that aren't 10 digits starting with 0" do
    [ "987654321", "09876543210", "1234567890", "abc" ].each do |input|
      user = build(phone_number: input)
      assert_not user.valid?, input
      assert_includes user.errors.attribute_names, :phone_number
    end
  end

  test "password needs at least 8 characters" do
    assert_not build(password: "1234567").valid?
    assert build(password: "12345678").valid?
  end

  test "rejects unknown role in validation and in the database" do
    assert_not build(role: "staff").valid?
    assert_raises(ActiveRecord::StatementInvalid) { users(:owner).update_column(:role, "staff") }
  end

  test "role label and initial" do
    assert_equal "Quản trị viên", users(:admin).role_label
    assert_equal "Thành viên", users(:owner).role_label
    assert_equal "C", users(:owner).initial
    assert_equal "Á", build(name: "ánh").initial
  end

  test "role_at and allowed_to? come from the membership only, also for admins" do
    staff = User.create!(name: "Em Hằng", phone_number: "0987111222", password: "password123")
    staff.place_memberships.create!(place: places(:tomo), role: "staff")

    assert_equal "owner", users(:owner).role_at(places(:tomo))
    assert_equal "staff", staff.role_at(places(:tomo))
    assert_nil users(:owner).role_at(places(:hiuhill))
    assert_nil users(:admin).role_at(places(:tomo))

    assert users(:owner).allowed_to?(:manage, places(:tomo))
    assert users(:owner).allowed_to?(:operate, places(:tomo))
    assert_not staff.allowed_to?(:manage, places(:tomo))
    assert staff.allowed_to?(:operate, places(:tomo))
    assert_not users(:owner).allowed_to?(:operate, places(:hiuhill))
    assert_not users(:admin).allowed_to?(:manage, places(:tomo))
    assert_not users(:admin).allowed_to?(:operate, places(:tomo))

    users(:admin).place_memberships.create!(place: places(:tomo), role: "staff")
    assert_equal "staff", users(:admin).role_at(places(:tomo))
    assert users(:admin).allowed_to?(:operate, places(:tomo))
    assert_not users(:admin).allowed_to?(:manage, places(:tomo))
    users(:admin).place_memberships.find_by!(place: places(:tomo)).update!(role: "owner")
    assert users(:admin).allowed_to?(:manage, places(:tomo))

    assert_raises(ArgumentError) { users(:owner).allowed_to?(:undo, places(:tomo)) }
  end
end
