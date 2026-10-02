require "test_helper"

class Admin::MembersControllerTest < ActionDispatch::IntegrationTest
  def log_in(user)
    post session_path, params: { phone_number: user.phone_number, password: "password123" }
  end

  def setup_token = flash[:setup_link].to_s.split("/").last

  setup do
    @staff = User.create!(name: "Em Hằng", phone_number: "0987111222", password: "password123")
    @staff_membership = @staff.place_memberships.create!(place: places(:tomo), role: "staff")
    log_in users(:owner)
  end

  test "homestay page lists members for owners only" do
    get admin_place_path("tomo-homestay")
    assert_select "#members", text: /Chị Lan \(bạn\).*Chủ.*Em Hằng.*Nhân viên/m
    assert_select "#members a[href=?]", edit_admin_place_member_path("tomo-homestay", @staff_membership)

    delete session_path
    log_in @staff
    get admin_place_path("tomo-homestay")
    assert_select "#members", 0
  end

  test "owner adds a staff member and gets a one-time set-password link" do
    assert_difference [ -> { User.count }, -> { places(:tomo).place_memberships.count } ], 1 do
      post admin_place_members_path("tomo-homestay"), params: { member: { name: "Anh Tuấn", phone_number: "0905 222 333", role: "staff" } }
    end
    user = User.find_by!(phone_number: "0905222333")
    membership = user.place_memberships.sole
    assert_equal [ "user", "staff", places(:tomo) ], [ user.role, membership.role, membership.place ]
    assert_redirected_to edit_admin_place_member_path("tomo-homestay", membership)
    assert_equal user, User.find_by_token_for(:password_setup, setup_token)
    follow_redirect!
    assert_select "[data-setup-link]"
  end

  test "an existing phone, typed any way, gets a generic error and creates nothing" do
    assert_no_difference [ -> { User.count }, -> { PlaceMembership.count } ] do
      post admin_place_members_path("tomo-homestay"), params: { member: { name: "X", phone_number: "+84 905 111 222", role: "staff" } } # users(:admin)
    end
    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /Số điện thoại này đã được dùng\. Nhờ quản trị viên thêm vào homestay\./
    assert_select "body", text: /Trung/, count: 0
  end

  test "invalid name or phone re-renders with errors" do
    post admin_place_members_path("tomo-homestay"), params: { member: { name: "", phone_number: "123", role: "staff" } }
    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /Tên/
  end

  test "owner changes a member's role; the last owner can't be demoted" do
    patch admin_place_member_path("tomo-homestay", @staff_membership), params: { place_membership: { role: "owner" } }
    assert_redirected_to admin_place_path("tomo-homestay")
    assert @staff_membership.reload.owner?

    patch admin_place_member_path("tomo-homestay", @staff_membership), params: { place_membership: { role: "staff" } }
    only_owner = place_memberships(:owner_tomo)
    patch admin_place_member_path("tomo-homestay", only_owner), params: { place_membership: { role: "staff" } }
    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /Homestay cần ít nhất một chủ\./
    assert only_owner.reload.owner?
  end

  test "owner removes a member (account kept); the last owner can't be removed" do
    delete admin_place_member_path("tomo-homestay", @staff_membership)
    assert_redirected_to admin_place_path("tomo-homestay")
    assert_not PlaceMembership.exists?(@staff_membership.id)
    assert User.exists?(@staff.id)

    delete admin_place_member_path("tomo-homestay", place_memberships(:owner_tomo))
    assert_redirected_to admin_place_path("tomo-homestay")
    assert_equal "Homestay cần ít nhất một chủ.", flash[:alert]
    assert PlaceMembership.exists?(place_memberships(:owner_tomo).id)
  end

  test "owner can step down when another owner remains, landing on a page staff can open" do
    @staff_membership.update!(role: "owner")
    patch admin_place_member_path("tomo-homestay", place_memberships(:owner_tomo)), params: { place_membership: { role: "staff" } }
    assert_redirected_to admin_place_path("tomo-homestay")
    assert place_memberships(:owner_tomo).reload.staff?
  end

  test "owner can leave when another owner remains, landing on the dashboard" do
    @staff_membership.update!(role: "owner")
    delete admin_place_member_path("tomo-homestay", place_memberships(:owner_tomo))
    assert_redirected_to admin_root_path
    assert_not users(:owner).places.exists?
  end

  test "set-password link only for members who belong to no one else's homestay" do
    post setup_link_admin_place_member_path("tomo-homestay", @staff_membership)
    assert_redirected_to edit_admin_place_member_path("tomo-homestay", @staff_membership)
    assert_not @staff.reload.authenticate("password123")
    assert_equal @staff, User.find_by_token_for(:password_setup, setup_token)

    @staff.place_memberships.create!(place: places(:hiuhill), role: "staff") # hiuhill isn't Chị Lan's
    post setup_link_admin_place_member_path("tomo-homestay", @staff_membership)
    assert_response :forbidden
    get edit_admin_place_member_path("tomo-homestay", @staff_membership)
    assert_select "button", text: /Tạo link/, count: 0

    post setup_link_admin_place_member_path("tomo-homestay", place_memberships(:owner_tomo)) # yourself
    assert_response :forbidden
  end

  test "staff get 403 on every members action; other homestays 404" do
    delete session_path
    log_in @staff
    get new_admin_place_member_path("tomo-homestay")
    assert_response :forbidden
    post admin_place_members_path("tomo-homestay"), params: { member: { name: "X", phone_number: "0905999888", role: "owner" } }
    assert_response :forbidden
    patch admin_place_member_path("tomo-homestay", @staff_membership), params: { place_membership: { role: "owner" } }
    assert_response :forbidden
    assert @staff_membership.reload.staff?
    delete admin_place_member_path("tomo-homestay", place_memberships(:owner_tomo))
    assert_response :forbidden
    get new_admin_place_member_path("hiuhill-homestay")
    assert_response :not_found
  end

  test "membership ids are scoped to the homestay in the URL" do
    other = User.create!(name: "Anh Bình", phone_number: "0987000001", password: "password123")
    hiuhill_membership = other.place_memberships.create!(place: places(:hiuhill))
    delete admin_place_member_path("tomo-homestay", hiuhill_membership)
    assert_response :not_found
    assert PlaceMembership.exists?(hiuhill_membership.id)
  end
end
