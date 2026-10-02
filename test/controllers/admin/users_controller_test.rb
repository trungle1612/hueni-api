require "test_helper"

class Admin::UsersControllerTest < ActionDispatch::IntegrationTest
  def log_in(user, password = "password123")
    post session_path, params: { phone_number: user.phone_number, password: }
  end

  # The one-time link shown to the admin; its token is the last path segment.
  def setup_token = flash[:setup_link].to_s.split("/").last

  setup { log_in users(:admin) }

  test "owners can't see or change users" do
    delete session_path
    log_in users(:owner)
    get admin_users_path
    assert_response :not_found
    get new_admin_user_path
    assert_response :not_found
    post admin_users_path, params: { user: { name: "X", phone_number: "0987000009", role: "admin" } }
    assert_response :not_found
    get edit_admin_user_path(users(:admin))
    assert_response :not_found
    post reset_password_admin_user_path(users(:admin))
    assert_response :not_found
    assert_not User.exists?(phone_number: "0987000009")
    assert users(:admin).reload.authenticate("password123")
  end

  test "list shows users with role, phone and homestays" do
    get admin_users_path
    assert_response :success
    assert_select "#user_#{users(:owner).id}", text: /Chị Lan.*0912 345 678.*tomo homestay/m
    assert_select "#user_#{users(:admin).id}", text: /Quản trị viên/
    assert_select "aside a.menu-active", text: /Người dùng/
  end

  test "creating a user shows a one-time link to set their password" do
    assert_difference -> { User.count }, 1 do
      post admin_users_path, params: { user: { name: "Chị Hoa", phone_number: "+84 987 654 321", role: "owner",
        place_ids: [ "", places(:tomo).id, places(:hiuhill).id ] } }
    end
    user = User.find_by!(phone_number: "0987654321")
    assert_equal [ places(:hiuhill), places(:tomo) ], user.places.order(:name).to_a
    assert user.owner?
    assert_redirected_to edit_admin_user_path(user)
    assert_equal user, User.find_by_token_for(:password_setup, setup_token)
    link = flash[:setup_link]
    assert_equal password_setup_url(token: setup_token), link

    follow_redirect!
    assert_select "[data-setup-link]", text: link
    get edit_admin_user_path(user)
    assert_select "[data-setup-link]", 0 # only once
  end

  test "invalid or duplicate phone number re-renders with an error" do
    [ "123", "0912 345 678" ].each do |phone_number|
      assert_no_difference -> { User.count } do
        post admin_users_path, params: { user: { name: "X", phone_number:, role: "owner" } }
      end
      assert_response :unprocessable_entity
      assert_select "[role=alert]", text: /Số điện thoại/
    end
  end

  test "edits name, phone, role and homestays" do
    patch admin_user_path(users(:owner)), params: { user: { name: "Chị Lan Anh", phone_number: "0912 000 111", role: "admin",
      place_ids: [ "", places(:hiuhill).id ] } }
    assert_redirected_to admin_users_path
    users(:owner).reload
    assert_equal [ "Chị Lan Anh", "0912000111", "admin", [ places(:hiuhill) ] ],
      [ users(:owner).name, users(:owner).phone_number, users(:owner).role, users(:owner).places.to_a ]
  end

  test "failed edit keeps the old homestays" do
    patch admin_user_path(users(:owner)), params: { user: { name: "", place_ids: [ "" ] } }
    assert_response :unprocessable_entity
    assert_equal [ places(:tomo) ], users(:owner).reload.places.to_a
  end

  test "admins can't change their own role" do
    patch admin_user_path(users(:admin)), params: { user: { name: "Trung", role: "owner" } }
    assert users(:admin).reload.admin?
  end

  test "a new link locks the old password, older links and every session" do
    users(:owner).sessions.create!(ip_address: "1.1.1.1", user_agent: "phone")
    post reset_password_admin_user_path(users(:owner))
    old_token = setup_token
    post reset_password_admin_user_path(users(:owner))

    assert_redirected_to edit_admin_user_path(users(:owner))
    assert_empty users(:owner).sessions.reload
    assert_not users(:owner).reload.authenticate("password123")
    assert_nil User.find_by_token_for(:password_setup, old_token)
    assert_equal users(:owner), User.find_by_token_for(:password_setup, setup_token)
  end

  test "admins can't reset their own password here" do
    post reset_password_admin_user_path(users(:admin))
    assert_response :not_found
    assert users(:admin).reload.authenticate("password123")
    get edit_admin_user_path(users(:admin))
    assert_select "button", text: /Tạo link đặt lại mật khẩu/, count: 0
  end
end
