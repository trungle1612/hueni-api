require "test_helper"

class UserTest < ActiveSupport::TestCase
  def build(**attrs)
    User.new(phone_number: "0987654321", name: "Chị Mai", password: "password123", **attrs)
  end

  test "valid with defaults; role defaults to owner" do
    user = build
    assert user.valid?
    assert user.owner?
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
    assert_equal "Chủ homestay", users(:owner).role_label
    assert_equal "C", users(:owner).initial
    assert_equal "Á", build(name: "ánh").initial
  end
end
