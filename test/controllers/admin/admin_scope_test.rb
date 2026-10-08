require "test_helper"

# #85: admins run accounts, not homestays. Without a membership every homestay page is out of scope.
class Admin::AdminScopeTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 10, 1, 12)
    post session_path, params: { phone_number: users(:admin).phone_number, password: "password123" }
  end

  test "a homestay's pages are not found for an admin who isn't a member" do
    booking = bookings(:limdim_confirmed)
    feed = calendar_feeds(:limdim_airbnb)
    owner = place_memberships(:owner_tomo)
    {
      admin_place_path("tomo-homestay") => :get,
      admin_place_calendar_path("tomo-homestay") => :get,
      admin_place_activity_path("tomo-homestay") => :get,
      admin_place_report_path("tomo-homestay") => :get,
      new_admin_place_booking_path("tomo-homestay") => :get,
      edit_admin_booking_path(booking) => :get,
      admin_booking_path(booking) => :patch,
      check_in_admin_booking_path(booking) => :post,
      new_admin_place_room_path("tomo-homestay") => :get,
      edit_admin_room_path(rooms(:garden)) => :get,
      admin_room_path(rooms(:garden)) => :patch,
      admin_room_calendar_feeds_path(rooms(:garden)) => :post,
      sync_admin_calendar_feed_path(feed) => :post,
      admin_calendar_feed_path(feed) => :delete,
      new_admin_place_member_path("tomo-homestay") => :get,
      edit_admin_place_member_path("tomo-homestay", owner) => :get
    }.each do |path, verb|
      public_send(verb, path)
      assert_response :not_found, "#{verb} #{path}"
    end
    assert_nil booking.reload.checked_in_at
  end

  test "menu entries lead nowhere private without a membership" do
    get admin_calendar_path
    assert_redirected_to admin_root_path
    get admin_report_path
    assert_redirected_to admin_root_path
    get admin_calendar_feeds_path
    assert_response :success
    assert_select "main", text: /Limdim|Garden/, count: 0
  end

  test "the menu has no Báo cáo for an admin who owns no homestay" do
    get admin_root_path
    assert_select "aside a[href='#{admin_report_path}']", count: 0
    assert_select "aside a[href='#{admin_users_path}']"
  end
end
