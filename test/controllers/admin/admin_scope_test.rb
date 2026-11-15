require "test_helper"

# #247: /admin is the admins' area. Owners and staff are sent to the PWA; their old /admin URLs open the matching screen.
class Admin::AdminScopeTest < ActionDispatch::IntegrationTest
  setup { travel_to Time.zone.local(2026, 10, 1, 12) }

  test "owners and staff are sent to the PWA from every /admin page, writes included" do
    registration = RegistrationRequest.create!(zalo_id: "zalo-lan", name: "Lan", phone_number: "0905999888", place_name: "Hieu Hil")
    staff = User.create!(name: "Bé Na", phone_number: "0987654321", password: "password123")
    places(:tomo).place_memberships.create!(user: staff, role: "staff")
    [ users(:owner), staff ].each do |user|
      sign_in_as user
      [ admin_root_path, admin_users_path, new_admin_user_path, edit_admin_user_path(user), admin_sync_runs_path, admin_invites_path,
        admin_announcements_path, admin_registration_request_path(registration) ].each do |path|
        get path
        assert_redirected_to pms_today_path, path
      end
      post admin_users_path, params: { user: { name: "X", phone_number: "0911222333", role: "admin" } }
      assert_redirected_to pms_today_path
      post admin_invites_path, params: { invite: { place_id: places(:tomo).id, role: "owner" } }
      assert_redirected_to pms_today_path
      patch approve_admin_registration_request_path(registration)
      assert_redirected_to pms_today_path
    end
    assert_nil User.find_by(phone_number: "0911222333")
    assert_empty Invite.all
    assert registration.reload.pending?
  end

  test "old owner URLs open the matching PWA screen on that homestay" do
    booking = bookings(:limdim_confirmed)
    {
      "/admin/calendar?from=2026-10-05" => "/lich?from=2026-10-05",
      "/admin/report?month=2026-09" => "/bao-cao?month=2026-09",
      "/admin/tim?q=mai" => "/tim?q=mai",
      "/admin/places/tomo-homestay" => "/hom-nay?co_so=tomo-homestay",
      "/admin/places/tomo-homestay/calendar?from=2026-10-05&x=1" => "/lich?co_so=tomo-homestay&from=2026-10-05",
      "/admin/places/tomo-homestay/activity" => "/nhat-ky?co_so=tomo-homestay",
      "/admin/places/tomo-homestay/report?period=7d" => "/bao-cao?co_so=tomo-homestay&period=7d",
      "/admin/places/tomo-homestay/bookings/new?room_id=#{rooms(:garden).id}&start_date=2026-10-05" =>
        "/dat-phong/moi?co_so=tomo-homestay&room_id=#{rooms(:garden).id}&start_date=2026-10-05",
      "/admin/places/tomo-homestay/members/new" => "/nhan-vien?co_so=tomo-homestay",
      "/admin/places/tomo-homestay/rooms/new" => "/phong/moi?co_so=tomo-homestay",
      "/admin/rooms" => "/phong",
      "/admin/rooms/#{rooms(:garden).id}/edit" => "/phong/#{rooms(:garden).id}/sua",
      "/admin/calendar_feeds" => "/kenh",
      "/admin/bookings/#{booking.id}/edit" => "/dat-phong/#{booking.id}",
      "/admin/bookings/#{booking.id}/history" => "/dat-phong/#{booking.id}"
    }.each do |old, new|
      get old
      assert_redirected_to "http://www.example.com#{new}", old
    end
  end

  test "?co_so= switches the PWA to a homestay you are a member of, and ignores others" do
    places(:hiuhill).place_memberships.create!(user: users(:owner), role: "owner")
    log_in users(:owner)
    get "/admin/places/hiuhill-homestay/calendar"
    follow_redirect!
    assert_response :success
    assert_equal "hiuhill-homestay", session[:pms_place]
    get pms_calendar_path(co_so: "unknown")
    assert_equal "hiuhill-homestay", session[:pms_place]
  end
end
