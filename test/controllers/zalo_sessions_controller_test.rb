require "test_helper"

class ZaloSessionsControllerTest < ActionDispatch::IntegrationTest
  def zalo(uid, link: nil, phone: nil)
    mock_zalo(uid, phone:)
    post link ? "/auth/zalo2?link=#{link}" : "/auth/zalo2"
    follow_redirect!
  end

  test "a linked Zalo id logs in, admin or not, and goes where they were headed" do
    get admin_calendar_path
    zalo "zalo-chi-lan"
    assert_redirected_to admin_calendar_url
    assert_equal 1, users(:owner).sessions.count

    delete session_path
    users(:admin).update!(zalo_id: "zalo-trung")
    zalo "zalo-trung"
    assert_redirected_to admin_root_url
    assert_equal 1, users(:admin).sessions.count
  end

  test "an unknown Zalo id logs nobody in and creates no account" do
    assert_no_difference [ "User.count", "Session.count" ] do
      zalo "zalo-unknown"
    end
    assert_redirected_to new_session_path
    follow_redirect!
    assert_select "[role=alert]", text: /Tài khoản Zalo này chưa được liên kết/
  end

  test "a blank uid is rejected, even with an unlinked user around" do
    assert_no_difference -> { Session.count } do
      zalo ""
      zalo "", link: "me"
    end
    assert_redirected_to new_session_path
    assert_nil users(:admin).reload.zalo_id
  end

  test "Zalo failure goes back to the login page with an alert" do
    OmniAuth.config.mock_auth[:zalo2] = :invalid_credentials
    post "/auth/zalo2"
    follow_redirect! # callback → OmniAuth failure endpoint
    follow_redirect! # → /auth/failure
    assert_redirected_to new_session_path
    follow_redirect!
    assert_select "[role=alert]", text: /Đăng nhập Zalo không thành công/
  ensure
    OmniAuth.config.mock_auth[:zalo2] = nil
  end

  test "the link page binds Zalo, logs in and consumes the link" do
    user = users(:owner)
    user.update!(zalo_id: nil)
    other_device = user.sessions.create!
    token = user.generate_token_for(:password_setup)

    get password_setup_path(token:)
    zalo "zalo-moi", link: "token"

    assert_redirected_to admin_root_url
    assert_equal "zalo-moi", user.reload.zalo_id
    assert_not_includes user.sessions, other_device
    assert_equal 1, user.sessions.count
    get password_setup_path(token:)
    assert_response :not_found
    assert_select "body", text: /Link đã hết hạn hoặc đã được dùng/
  end

  test "link=token without having opened a valid link logs nobody in" do
    zalo "zalo-moi", link: "token"
    assert_redirected_to new_session_path
    assert_nil User.find_by(zalo_id: "zalo-moi")
  end

  test "a Zalo id already linked to someone else can't be bound to a second user" do
    users(:admin).update!(zalo_id: "zalo-trung")
    token = users(:owner).generate_token_for(:password_setup)
    get password_setup_path(token:)
    zalo "zalo-trung", link: "token"

    assert_redirected_to password_setup_path(token:)
    assert_equal "zalo-chi-lan", users(:owner).reload.zalo_id
    assert_equal users(:owner), User.find_by_token_for(:password_setup, token)
    assert_equal 0, Session.count
  end

  test "logged in, Liên kết Zalo binds to the current user only" do
    log_in users(:admin) # links "zalo-<id>" through the helper
    users(:admin).update!(zalo_id: nil)
    get admin_root_path

    zalo "zalo-trung", link: "me"
    assert_redirected_to admin_root_path
    assert_equal "zalo-trung", users(:admin).reload.zalo_id
    assert_equal "zalo-chi-lan", users(:owner).reload.zalo_id

    zalo "zalo-chi-lan", link: "me"
    assert_equal "zalo-trung", users(:admin).reload.zalo_id
  end

  test "Liên kết Zalo while logged out does nothing" do
    zalo "zalo-moi", link: "me"
    assert_redirected_to new_session_path
    assert_nil User.find_by(zalo_id: "zalo-moi")
  end

  test "unlinked non-admins see the Liên kết Zalo banner on the dashboard" do
    log_in users(:owner)
    assert_select "#link_zalo", 0
    users(:owner).update!(zalo_id: nil)
    get admin_root_path
    assert_select "#link_zalo form[action$='?link=me']"
  end

  test "an unknown Zalo id with an owner's phone number links that owner and logs in (#98)" do
    users(:owner).update!(zalo_id: nil)
    zalo "zalo-moi", phone: "84912345678" # Zalo's format; stored as 0912345678
    assert_redirected_to admin_root_url
    assert_equal "zalo-moi", users(:owner).reload.zalo_id
    assert_equal 1, users(:owner).sessions.count
  end

  test "the phone number never links an admin, an already linked user, or a blank number" do
    users(:admin).update!(zalo_id: nil)
    zalo "zalo-moi", phone: "84905111222"
    assert_nil users(:admin).reload.zalo_id

    zalo "zalo-moi", phone: "84912345678" # Chị Lan is linked to zalo-chi-lan already
    assert_equal "zalo-chi-lan", users(:owner).reload.zalo_id

    users(:owner).update!(zalo_id: nil)
    zalo "zalo-moi", phone: ""
    assert_nil users(:owner).reload.zalo_id
    assert_equal 0, Session.count
    assert_redirected_to new_session_path
  end
end
