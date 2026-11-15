require "test_helper"

class Admin::DashboardControllerTest < ActionDispatch::IntegrationTest
  test "requires login" do
    get admin_root_path
    assert_redirected_to new_session_path
  end

  test "root shows the login page with the Zalo site verification tag" do
    get "/"
    assert_response :success
    assert_includes response.body, 'name="zalo-platform-site-verification"'
    assert_select "form[action=?]", session_path
  end

  test "root sends owners and staff to the PWA, admins to /admin" do
    log_in users(:owner)
    get "/"
    assert_redirected_to pms_today_url

    sign_in_as users(:admin)
    get "/"
    assert_redirected_to admin_root_url
  end

  test "public endpoints stay public" do
    get "/v1/vacancy"
    assert_response :success
    get "/up"
    assert_response :success
  end

  test "admins get the admin menu, name and role" do
    users(:admin).update!(name: "ánh")
    log_in users(:admin)
    get admin_root_path
    assert_select "h1", "Tổng quan"
    assert_select "aside a", 5
    { "/admin" => "Tổng quan", "/admin/users" => "Người dùng", "/admin/dong-bo" => "Đồng bộ", "/admin/ma-moi" => "Mã mời",
      "/admin/thong-bao" => "Thông báo" }.each { |href, label| assert_select "aside a[href=?]", href, text: /#{label}/ }
    assert_select ".dock a", 5
    assert_select ".avatar", text: "Á"
    assert_select "aside", text: /ánh.*Quản trị viên/m
    assert_select "aside button", text: "Đăng xuất"
  end

  test "every homestay's members and failing feeds, no guest data; a member's homestay opens in the PWA" do
    travel_to Time.zone.local(2026, 10, 1, 12)
    calendar_feeds(:limdim_airbnb).update_columns(last_error: "timeout", last_error_at: Time.current)
    RegistrationRequest.create!(name: "Chị Hoa", phone_number: "0912000111", place_name: "Nhà Hoa", zalo_id: "z-hoa")
    log_in users(:admin)
    get admin_root_path
    assert_select "#pending_registrations", text: /1 yêu cầu đăng ký chờ duyệt/
    assert_select "#all_places li", 2
    assert_select "#all_places li", text: /tomo homestay.*Kênh OTA lỗi: 1.*Chị Lan · Chủ/m
    assert_select "#all_places li", text: /Hiu Hill Homestay.*Chưa có thành viên/m
    assert_select "#all_places a", count: 0
    assert_select "main", text: /Anh Minh|Limdim/, count: 0

    places(:hiuhill).place_memberships.create!(user: users(:admin), role: "owner")
    get admin_root_path
    assert_select "#all_places a[href=?]", pms_today_path(co_so: "hiuhill-homestay"), text: "Hiu Hill Homestay"
  end
end
