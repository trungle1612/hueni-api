require "test_helper"

class Admin::RoomsHelperTest < ActionView::TestCase
  test "room_title adds Phòng unless the owner already wrote it" do
    assert_equal [ "Phòng 101", "Phòng gia đình", "phòng Sen" ], [ room_title("101"), room_title("Phòng gia đình"), room_title("phòng Sen") ]
  end
end
