require "test_helper"

# Zalo webhook user.revoke.consent (#225).
class MiniApp::ZaloWebhooksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @config = Rails.configuration.x.zalo_app_id, Rails.configuration.x.zalo_api_key
    Rails.configuration.x.zalo_app_id = "app-1"
    Rails.configuration.x.zalo_api_key = "api-key"
    users(:owner).update!(zalo_id: "zalo-chi-lan")
  end

  teardown { Rails.configuration.x.zalo_app_id, Rails.configuration.x.zalo_api_key = @config }

  def revoke(user_id, event: "user.revoke.consent", app_id: "app-1", key: "api-key")
    payload = { event:, appId: app_id, userId: user_id, timestamp: 1670553442564 }
    # keys A→Z: appId, event, timestamp, userId
    signature = Digest::SHA256.hexdigest("#{app_id}#{event}1670553442564#{user_id}#{key}")
    post api_v1_zalo_webhook_path, params: payload.to_json, headers: { "Content-Type" => "application/json", "x-zevent-signature" => signature }
  end

  test "a signed user.revoke.consent deletes the account like Xoá tài khoản; its tokens stop working" do
    staff = User.create!(name: "Bé Na", phone_number: "0987654321", password: "password123", zalo_id: "zalo-na")
    places(:tomo).place_memberships.create!(user: staff, role: "staff")
    token = staff.api_tokens.create!.token

    revoke("zalo-na")
    assert_response :ok
    assert staff.reload.deleted?
    assert_nil staff.zalo_id
    assert_not staff.place_memberships.exists?
    get api_v1_me_path, headers: { "Authorization" => "Bearer #{token}" }
    assert_response :unauthorized

    revoke("zalo-na") # Zalo retries
    assert_response :ok
  end

  test "a Zalo id with only a registration request loses the request" do
    RegistrationRequest.create!(zalo_id: "zalo-hoa", name: "Hoa", phone_number: "0905123456", place_name: "Hoa Sen Homestay")
    revoke("zalo-hoa")
    assert_response :ok
    assert_not RegistrationRequest.exists?(zalo_id: "zalo-hoa")
  end

  test "a bad or missing signature is refused and changes nothing" do
    revoke("zalo-chi-lan", key: "wrong")
    assert_response :unauthorized
    post api_v1_zalo_webhook_path, params: { event: "user.revoke.consent", appId: "app-1", userId: "zalo-chi-lan" }, as: :json
    assert_response :unauthorized
    post api_v1_zalo_webhook_path, params: "nope", headers: { "Content-Type" => "application/json" }
    assert_response :unauthorized
    assert_not users(:owner).reload.deleted?
  end

  test "an unknown user, another event or another app answers 200 and changes nothing" do
    revoke("zalo-unknown")
    assert_response :ok
    revoke("zalo-chi-lan", event: "versions.review.done")
    assert_response :ok
    revoke("zalo-chi-lan", app_id: "other-app")
    assert_response :ok
    assert_not users(:owner).reload.deleted?
  end

  test "no API key configured: every event is refused" do
    Rails.configuration.x.zalo_api_key = nil
    revoke("zalo-chi-lan", key: "")
    assert_response :unauthorized
    assert_not users(:owner).reload.deleted?
  end
end
