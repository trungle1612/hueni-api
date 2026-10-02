require "test_helper"

class PasswordSetupsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:owner)
    @token = @user.generate_token_for(:password_setup)
  end

  def set_password(password, confirmation = password, token: @token)
    patch password_setup_path(token:), params: { user: { password:, password_confirmation: confirmation } }
  end

  test "link opens the set-password page without logging in" do
    get password_setup_path(token: @token)
    assert_response :success
    assert_select "h1", "Đặt mật khẩu"
    assert_select "body", text: /Chị Lan.*0912 345 678/m
  end

  test "setting a password logs the owner in, and the link then stops working" do
    set_password "mat-khau-moi"
    assert_redirected_to admin_root_url
    follow_redirect!
    assert_select "h1", "Tổng quan"
    assert @user.reload.authenticate("mat-khau-moi")

    get password_setup_path(token: @token)
    assert_response :not_found
    assert_select "body", text: /Link đã hết hạn hoặc đã được dùng/
  end

  test "link expires after 7 days" do
    travel 7.days + 1.minute
    get password_setup_path(token: @token)
    assert_response :not_found
    set_password "mat-khau-moi"
    assert_response :not_found
    assert @user.reload.authenticate("password123")
  end

  test "blank, short or mismatched passwords are rejected and the link stays valid" do
    [ [ "", "" ], [ "1234567", "1234567" ], [ "mat-khau-moi", "mat-khau-khac" ] ].each do |password, confirmation|
      set_password password, confirmation
      assert_response :unprocessable_entity
      assert_select "[role=alert]"
    end
    assert @user.reload.authenticate("password123")
    assert_equal @user, User.find_by_token_for(:password_setup, @token)
  end

  test "garbage token is not found" do
    get password_setup_path(token: "nope")
    assert_response :not_found
  end
end
