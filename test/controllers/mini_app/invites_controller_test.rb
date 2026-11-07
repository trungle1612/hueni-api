require "test_helper"

# Mã mời (#211): owners make, list and revoke staff codes for their homestay.
class MiniApp::InvitesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @staff = User.create!(name: "Bé Na", phone_number: "0987654321", password: "password123", zalo_id: "zalo-na")
    places(:tomo).place_memberships.create!(user: @staff, role: "staff")
    @other = User.create!(name: "Chủ khác", phone_number: "0911111111", password: "password123", zalo_id: "zalo-khac")
    places(:hiuhill).place_memberships.create!(user: @other, role: "owner")
    @tokens = { owner: users(:owner).api_tokens.create!.token, staff: @staff.api_tokens.create!.token, other: @other.api_tokens.create!.token }
  end

  def as(who, verb, path, params = {}) = send(verb, path, params:, headers: { "Authorization" => "Bearer #{@tokens.fetch(who)}" }, as: :json)
  def body = response.parsed_body

  test "an owner makes a staff code (7 days, one use), lists the usable ones and revokes one" do
    travel_to Time.zone.local(2026, 11, 8, 10)
    as :owner, :post, api_v1_place_invites_path(places(:tomo)), { invite: { role: "owner", max_uses: 20 } }
    assert_response :created
    invite = body["invite"]
    assert_match(/\A[A-HJKMNP-Z2-9]{4}-[A-HJKMNP-Z2-9]{4}\z/, invite["code"])
    assert_equal [ "staff", 1, "2026-11-15T10:00:00.000+07:00" ], invite.values_at("role", "uses_left", "expires_at")

    places(:tomo).invites.create!(created_by: users(:owner), expires_at: 1.minute.ago)
    as :owner, :get, api_v1_place_invites_path(places(:tomo))
    assert_equal [ invite["id"] ], body["invites"].pluck("id") # not the expired one

    as :owner, :delete, api_v1_invite_path(invite["id"])
    assert_response :no_content
    assert_not Invite.exists?(invite["id"])
  end

  test "staff can't make or revoke codes; another homestay's code is not found" do
    invite = places(:tomo).invites.create!(created_by: users(:owner))
    as :staff, :post, api_v1_place_invites_path(places(:tomo))
    assert_response :forbidden
    as :staff, :get, api_v1_place_invites_path(places(:tomo))
    assert_response :forbidden
    as :staff, :delete, api_v1_invite_path(invite)
    assert_response :forbidden
    as :other, :delete, api_v1_invite_path(invite)
    assert_response :not_found
    as :other, :post, api_v1_place_invites_path(places(:tomo))
    assert_response :not_found
    assert_equal 1, Invite.count
  end
end
