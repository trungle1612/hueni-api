require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  def log_in(email, password = "password123")
    post session_path, params: { email_address: email, password: password }
  end

  test "login page renders" do
    get new_session_path
    assert_response :success
    assert_select "h1, h2", text: "Đăng nhập"
  end

  test "correct credentials start a session and go to admin" do
    assert_difference -> { users(:owner).sessions.count }, 1 do
      log_in "lan@example.com"
    end
    assert_redirected_to admin_root_url
  end

  test "email casing and spaces don't matter" do
    log_in "  LAN@Example.com "
    assert_redirected_to admin_root_url
  end

  test "wrong password goes back to login with an error and no session" do
    assert_no_difference -> { Session.count } do
      log_in "lan@example.com", "wrong-password"
    end
    assert_redirected_to new_session_path
    follow_redirect!
    assert_select "[role=alert]", text: /Email hoặc mật khẩu không đúng/
  end

  test "logout ends only this device's session" do
    other_device = users(:owner).sessions.create!(ip_address: "1.1.1.1", user_agent: "phone")
    log_in "lan@example.com"

    delete session_path

    assert_redirected_to new_session_path
    assert_equal [ other_device ], users(:owner).sessions.reload.to_a
    get admin_root_path
    assert_redirected_to new_session_path
  end

  test "session of a deleted user no longer works" do
    log_in "lan@example.com"
    users(:owner).destroy!
    get admin_root_path
    assert_redirected_to new_session_path
  end

  test "after a stale logout, logging in goes to admin instead of the logout URL" do
    delete session_path
    assert_redirected_to new_session_path

    log_in "lan@example.com"
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
end
