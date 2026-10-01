require "test_helper"

class Admin::DashboardControllerTest < ActionDispatch::IntegrationTest
  def log_in(user)
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end

  test "requires login" do
    get admin_root_path
    assert_redirected_to new_session_path
  end

  test "root redirects to admin" do
    get root_path
    assert_redirected_to "/admin"
  end

  test "shows the dashboard to a logged-in user" do
    log_in users(:owner)
    get admin_root_path
    assert_response :success
    assert_select "h1", "Tổng quan"
  end

  test "public endpoints stay public" do
    get "/v1/vacancy"
    assert_response :success
    get "/up"
    assert_response :success
  end

  test "owner sees menu without users item; disabled items are not links" do
    log_in users(:owner)
    get admin_root_path

    assert_select "aside a[href='/admin']", text: /Tổng quan/
    assert_select "aside", text: /Lịch phòng/
    assert_select "aside a", text: /Lịch phòng/, count: 0
    assert_select "aside", text: /Người dùng/, count: 0
    assert_select ".dock a[href='/admin']"
  end

  test "admin also sees the users item" do
    log_in users(:admin)
    get admin_root_path
    assert_select "aside", text: /Người dùng/
  end

  test "shows name, role and avatar initial, including Vietnamese letters" do
    users(:owner).update!(name: "ánh")
    log_in users(:owner)
    get admin_root_path

    assert_select ".avatar", text: "Á"
    assert_select "aside", text: /ánh/
    assert_select "aside", text: /Chủ homestay/
    assert_select "aside button", text: "Đăng xuất"
  end

  test "dashboard shows the empty state" do
    log_in users(:owner)
    get admin_root_path
    assert_select "main", text: /Chưa có homestay nào/
  end
end
