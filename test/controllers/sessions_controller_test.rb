require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  def log_in_with_password(phone, password = "password123")
    post session_path, params: { phone_number: phone, password: password }
  end

  test "login page offers registration through the same Zalo login" do
    get new_session_path
    assert_select "form[action$='register=1'] button", text: "Đăng ký làm chủ homestay bằng Zalo"
  end

  test "login page renders" do
    get new_session_path
    assert_response :success
    assert_select "h1, h2", text: "Đăng nhập"
  end

  test "login page leads with Zalo; the password form is for admins" do
    get new_session_path
    assert_select "form[action='/auth/zalo2'] button", "Đăng nhập bằng Zalo"
    assert_select "details summary", "Quản trị viên đăng nhập bằng mật khẩu"
    assert_select "details:not([open]) input[name=password]"
  end

  test "admin with correct credentials starts a session and goes to admin" do
    assert_difference -> { users(:admin).sessions.count }, 1 do
      log_in_with_password "0905111222"
    end
    assert_redirected_to admin_root_url
  end

  test "phone number spacing and +84 prefix don't matter" do
    log_in_with_password "+84 905.111-222"
    assert_redirected_to admin_root_url
  end

  test "wrong password goes back to login with an error and no session" do
    assert_no_difference -> { Session.count } do
      log_in_with_password "0905111222", "wrong-password"
    end
    assert_redirected_to new_session_path(admin: 1)
    follow_redirect!
    assert_select "[role=alert]", text: /Số điện thoại hoặc mật khẩu không đúng/
    assert_select "details[open] input[name=password]"
  end

  test "a non-admin with the right password is refused with the wrong-password message" do
    assert_no_difference -> { Session.count } do
      log_in_with_password "0912345678"
    end
    assert_redirected_to new_session_path(admin: 1)
    follow_redirect!
    assert_select "[role=alert]", text: /Số điện thoại hoặc mật khẩu không đúng/
  end

  test "logout ends only this device's session" do
    other_device = users(:admin).sessions.create!(ip_address: "1.1.1.1", user_agent: "phone")
    log_in_with_password "0905111222"

    delete session_path

    assert_redirected_to new_session_path
    assert_equal [ other_device ], users(:admin).sessions.reload.to_a
    get admin_root_path
    assert_redirected_to new_session_path
  end

  test "session of a deleted user no longer works" do
    log_in_with_password "0905111222"
    users(:admin).destroy!
    get admin_root_path
    assert_redirected_to new_session_path
  end

  test "after a stale logout, logging in goes to admin instead of the logout URL" do
    delete session_path
    assert_redirected_to new_session_path

    log_in_with_password "0905111222"
    assert_redirected_to admin_root_url
  end

  test "login page works on older phone browsers" do
    get new_session_path, headers: { "User-Agent" => "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1" }
    assert_response :success
  end

  test "a HEAD request to a page is remembered like GET" do
    head admin_root_path
    assert_equal admin_root_url, session[:return_to_after_authenticating]
  end

  test "without Zalo keys the button is disabled with a notice instead of failing at Zalo" do
    OmniAuth.config.test_mode = false
    configured, Rails.configuration.x.zalo_configured = Rails.configuration.x.zalo_configured, false
    get new_session_path
    assert_select "form[action='/auth/zalo2']", 0
    assert_select "button[disabled]", "Đăng nhập bằng Zalo"
    assert_select "[role=alert]", text: /Chưa cấu hình Zalo/
  ensure
    OmniAuth.config.test_mode = true
    Rails.configuration.x.zalo_configured = configured
  end
end
