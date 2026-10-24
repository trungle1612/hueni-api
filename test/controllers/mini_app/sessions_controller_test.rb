require "test_helper"

# Mini App sign-in (#152).
class MiniApp::SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @secret = Rails.configuration.x.zalo_app_secret
    Rails.configuration.x.zalo_app_secret = "test-secret"
    users(:owner).update!(zalo_id: "zalo-chi-lan")
  end

  teardown { Rails.configuration.x.zalo_app_secret = @secret }

  def zalo_me(token, body)
    stub_request(:get, "https://graph.zalo.me/v2.0/me?fields=id,name")
      .with(headers: { "access_token" => token, "appsecret_proof" => OpenSSL::HMAC.hexdigest("SHA256", "test-secret", token) })
      .to_return(body: body.to_json)
  end

  def bearer(token) = { "Authorization" => "Bearer #{token}" }

  test "a Zalo access token becomes an API token; /me lists the homestays with the role; logout ends it" do
    zalo_me("zmp-token", { id: "zalo-chi-lan", name: "Lan" })
    post app_v1_session_path, params: { access_token: "zmp-token" }, as: :json
    assert_response :created
    token = response.parsed_body["token"]
    assert_equal 32, token.size
    assert_equal({ "id" => places(:tomo).id, "slug" => "tomo-homestay", "name" => places(:tomo).name, "role" => "owner" }, response.parsed_body["places"].sole)
    assert_not ApiToken.exists?(token_digest: token) # only the digest is kept
    assert_equal "*", response.headers["Access-Control-Allow-Origin"]

    get app_v1_me_path, headers: bearer(token)
    assert_response :success
    assert_equal users(:owner).name, response.parsed_body.dig("user", "name")

    delete app_v1_session_path, headers: bearer(token)
    assert_response :no_content
    get app_v1_me_path, headers: bearer(token)
    assert_response :unauthorized
    assert_equal "unauthorized", response.parsed_body["error"]
  end

  test "an unknown Zalo account is not registered; a token Zalo refuses (or another app's) is rejected" do
    zalo_me("stranger", { id: "zalo-nobody", name: "X" })
    post app_v1_session_path, params: { access_token: "stranger" }, as: :json
    assert_response :forbidden
    assert_equal "not_registered", response.parsed_body["error"]

    zalo_me("bad", { error: 452, message: "Invalid access token" })
    post app_v1_session_path, params: { access_token: "bad" }, as: :json
    assert_response :unauthorized
    assert_equal "zalo_rejected", response.parsed_body["error"]

    post app_v1_session_path, params: { access_token: "" }, as: :json
    assert_response :unauthorized
    assert_equal 0, ApiToken.count
  end

  test "tokens last 30 days from the last use; reset_login revokes them; no token, no access" do
    token = users(:owner).api_tokens.create!.token
    travel 29.days
    get app_v1_me_path, headers: bearer(token)
    assert_response :success # renewed: 30 more days
    travel 29.days
    get app_v1_me_path, headers: bearer(token)
    assert_response :success
    travel 31.days
    get app_v1_me_path, headers: bearer(token)
    assert_response :unauthorized

    token = users(:owner).api_tokens.create!.token
    users(:owner).reset_login!
    get app_v1_me_path, headers: bearer(token)
    assert_response :unauthorized
    get app_v1_me_path
    assert_response :unauthorized
  end

  test "CORS preflight answers without a token" do
    process :options, "/app/v1/me", headers: { "Origin" => "https://h5.zdn.vn", "Access-Control-Request-Method" => "GET" }
    assert_response :no_content
    assert_equal "Authorization, Content-Type", response.headers["Access-Control-Allow-Headers"]
  end
end
