require "test_helper"

# Mã mời (#211): admins only, for any homestay.
class Admin::InvitesControllerTest < ActionDispatch::IntegrationTest
  test "an admin makes a code for any homestay (role, uses, days), sees it under menu Mã mời and revokes it" do
    log_in users(:admin) # member of no homestay
    get admin_invites_path
    assert_response :success
    assert_select "a.menu-active[href=?]", admin_invites_path

    freeze_time do
      post admin_invites_path, params: { invite: { place_id: places(:hiuhill).id, role: "owner", max_uses: 5, days: 14 } }
      assert_redirected_to admin_invites_path
      assert_equal [ "owner", 5, 14.days.from_now, users(:admin) ], places(:hiuhill).invites.sole.values_at(:role, :max_uses, :expires_at, :created_by)
    end
    invite = places(:hiuhill).invites.sole
    follow_redirect!
    assert_select "#invite_#{invite.id}", text: /#{invite.display_code}.*Chủ.*#{places(:hiuhill).name}.*Còn 5 lần/m

    post admin_invites_path, params: { invite: { place_id: places(:tomo).id, role: "staff", max_uses: 50, days: 7 } }
    assert_empty places(:tomo).invites
    assert flash[:alert].present?

    delete admin_invite_path(invite)
    assert_not Invite.exists?(invite.id)
  end

  test "owners and staff get 404 and no menu entry" do
    invite = places(:tomo).invites.create!(created_by: users(:admin))
    log_in users(:owner)
    get admin_place_path("tomo-homestay")
    assert_select "a[href=?]", admin_invites_path, 0
    assert_no_difference -> { Invite.count } do
      get admin_invites_path
      assert_response :not_found
      post admin_invites_path, params: { invite: { place_id: places(:tomo).id, role: "staff", max_uses: 1, days: 7 } }
      assert_response :not_found
      delete admin_invite_path(invite)
      assert_response :not_found
    end
  end
end
