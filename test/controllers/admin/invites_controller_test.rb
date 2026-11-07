require "test_helper"

# Mã mời on Thành viên (#211).
class Admin::InvitesControllerTest < ActionDispatch::IntegrationTest
  test "an owner makes a staff code (7 days, one use, extra params ignored), sees it on the homestay page and revokes it" do
    log_in users(:owner)
    freeze_time do
      post admin_place_invites_path("tomo-homestay"), params: { invite: { role: "owner", max_uses: 20, days: 30 } }
      invite = places(:tomo).invites.sole
      assert_equal [ "staff", 1, 7.days.from_now, users(:owner) ], [ invite.role, invite.max_uses, invite.expires_at, invite.created_by ]
      assert_redirected_to admin_place_path("tomo-homestay", anchor: "members")
    end
    invite = places(:tomo).invites.sole
    follow_redirect!
    assert_select "#invites_place_#{places(:tomo).id}", text: /#{invite.display_code}.*Nhân viên.*Còn 1 lần/m
    assert_select "#invites_place_#{places(:tomo).id} select", 0

    delete admin_place_invite_path("tomo-homestay", invite)
    assert_not Invite.exists?(invite.id)
  end

  test "menu Mã mời lists the codes of every homestay I own; create and Thu hồi come back to it" do
    log_in users(:owner)
    get admin_invites_path
    assert_response :success
    assert_select "a.menu-active[href=?]", admin_invites_path
    assert_select "#tomo-homestay h2", places(:tomo).name
    assert_select "#hiuhill-homestay", 0

    post admin_place_invites_path("tomo-homestay"), headers: { "Referer" => admin_invites_url }
    assert_redirected_to admin_invites_url
    follow_redirect!
    assert_select "#tomo-homestay", text: /#{places(:tomo).invites.sole.display_code}/
  end

  test "an admin member picks the role, uses and days: an owner code for Zalo review" do
    places(:tomo).place_memberships.create!(user: users(:admin), role: "owner")
    log_in users(:admin)
    get admin_place_path("tomo-homestay")
    assert_select "#invites_place_#{places(:tomo).id} select[name='invite[role]']"
    freeze_time do
      post admin_place_invites_path("tomo-homestay"), params: { invite: { role: "owner", max_uses: 5, days: 14 } }
      assert_equal [ "owner", 5, 14.days.from_now ], places(:tomo).invites.sole.values_at(:role, :max_uses, :expires_at)
    end
    post admin_place_invites_path("tomo-homestay"), params: { invite: { role: "staff", max_uses: 50, days: 7 } }
    assert_equal 1, places(:tomo).invites.count
    assert flash[:alert].present?
  end

  test "staff get 403; another homestay's codes are 404" do
    staff = User.create!(name: "Em Hằng", phone_number: "0987111222", password: "password123")
    staff.place_memberships.create!(place: places(:tomo), role: "staff")
    other = places(:hiuhill).invites.create!(created_by: users(:admin))

    log_in staff
    post admin_place_invites_path("tomo-homestay")
    assert_response :forbidden
    get admin_place_path("tomo-homestay")
    assert_select "#invites_place_#{places(:tomo).id}", 0
    assert_select "a[href=?]", admin_invites_path, 0
    get admin_invites_path
    assert_response :forbidden

    delete session_path
    log_in users(:owner)
    assert_no_difference -> { Invite.count } do
      post admin_place_invites_path("hiuhill-homestay")
      assert_response :not_found
      delete admin_place_invite_path("tomo-homestay", other)
      assert_response :not_found
    end
  end
end
