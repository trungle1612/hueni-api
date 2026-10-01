require "test_helper"

class UserTest < ActiveSupport::TestCase
  def build(**attrs)
    User.new(email_address: "new@example.com", name: "Chị Mai", password: "password123", **attrs)
  end

  test "valid with defaults; role defaults to owner" do
    user = build
    assert user.valid?
    assert user.owner?
  end

  test "requires name and email" do
    user = build(name: "", email_address: "")
    assert_not user.valid?
    assert_includes user.errors.attribute_names, :name
    assert_includes user.errors.attribute_names, :email_address
  end

  test "normalizes and uniquely indexes email" do
    assert_equal "lan@example.com", build(email_address: "  LAN@Example.com ").email_address
    assert_not build(email_address: "LAN@example.com").valid?
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
