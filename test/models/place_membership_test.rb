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
end
