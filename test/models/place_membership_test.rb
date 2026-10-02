require "test_helper"

class PlaceMembershipTest < ActiveSupport::TestCase
  test "links users and places both ways" do
    assert_equal [ places(:tomo) ], users(:owner).places.to_a
    assert_equal [ users(:owner) ], places(:tomo).users.to_a
  end

  test "a user can belong to a place only once" do
    duplicate = PlaceMembership.new(user: users(:owner), place: places(:tomo))
    assert_not duplicate.valid?
    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save(validate: false) }
  end

  test "db enforces user and place foreign keys" do
    assert_raises(ActiveRecord::InvalidForeignKey) do
      PlaceMembership.new(user_id: 0, place: places(:tomo)).save(validate: false)
    end
    assert_raises(ActiveRecord::InvalidForeignKey) do
      PlaceMembership.new(user: users(:owner), place_id: 0).save(validate: false)
    end
  end

  test "deleting a user deletes their memberships" do
    assert_difference -> { PlaceMembership.count }, -1 do
      users(:owner).destroy!
    end
  end

  test "role is owner by default, staff allowed, anything else rejected" do
    membership = PlaceMembership.new(user: users(:admin), place: places(:hiuhill))
    assert membership.owner?
    membership.role = "staff"
    assert membership.valid?
    membership.role = "boss"
    assert_not membership.valid?
    assert_raises(ActiveRecord::StatementInvalid) { place_memberships(:owner_tomo).update_column(:role, "boss") }
  end

  test "a homestay keeps at least one owner" do
    only_owner = place_memberships(:owner_tomo)
    assert_not only_owner.update(role: "staff")
    assert_includes only_owner.errors[:base], "Homestay cần ít nhất một chủ."
    assert_not only_owner.reload.destroy
    assert PlaceMembership.exists?(only_owner.id)

    co_owner = User.create!(name: "Anh Tuấn", phone_number: "0905222333", password: "password123")
    co_owner.place_memberships.create!(place: places(:tomo))
    assert only_owner.update(role: "staff")
    assert only_owner.destroy
  end
end
