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

  test "a token Zalo refuses (or another app's) is rejected" do
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
    assert_equal "Authorization, Content-Type, X-Registration-Token", response.headers["Access-Control-Allow-Headers"]
  end

  test "like the web: the Zalo phone links an owner or staff member without Zalo (#98), never an admin" do
    staff = User.create!(name: "Bé Na", phone_number: "0987654321", password: "password123")
    zalo_me("zmp-na", { id: "zalo-na", name: "Na" })
    stub_request(:get, "https://graph.zalo.me/v2.0/me/info")
      .with(headers: { "access_token" => "zmp-na", "code" => "phone-code", "secret_key" => "test-secret" })
      .to_return(body: { data: { number: "84987654321" }, error: 0 }.to_json)
    post app_v1_session_path, params: { access_token: "zmp-na", phone_token: "phone-code" }, as: :json
    assert_response :created
    assert_equal "zalo-na", staff.reload.zalo_id

    users(:admin).update!(phone_number: "0911222333")
    zalo_me("zmp-x", { id: "zalo-x", name: "X" })
    stub_request(:get, "https://graph.zalo.me/v2.0/me/info").with(headers: { "code" => "admin-code" })
      .to_return(body: { data: { number: "84911222333" } }.to_json)
    post app_v1_session_path, params: { access_token: "zmp-x", phone_token: "admin-code" }, as: :json
    assert_response :forbidden
    assert_nil users(:admin).reload.zalo_id
  end

  test "like /dang-ky: an unknown Zalo registers with the registration token, corrects it while pending, signs in once approved" do
    place = Place.create!(slug: "nha-hanh", name: "Nhà Hạnh", phone: "0234111222") # no owner yet
    zalo_me("zmp-new", { id: "zalo-new", name: "Chị Hạnh" })
    post app_v1_session_path, params: { access_token: "zmp-new" }, as: :json
    assert_response :forbidden
    assert_equal [ "not_registered", nil ], response.parsed_body.values_at("error", "registration")
    headers = { "X-Registration-Token" => response.parsed_body["registration_token"] }

    form = { name: "Chị Hạnh", phone_number: "0933 111 222", place_name: "Nhà Hạnh", maps_url: "" }
    assert_enqueued_jobs 1, only: NotifyRegistrationJob do
      post app_v1_registration_path, params: { registration: form }, headers:, as: :json
    end
    assert_response :created
    request = RegistrationRequest.sole
    assert_equal [ "zalo-new", "Chị Hạnh", place, "0933111222" ], [ request.zalo_id, request.zalo_name, request.place, request.phone_number ]
    assert_equal "pending", response.parsed_body.dig("registration", "status")

    post app_v1_registration_path, params: { registration: form }, headers:, as: :json
    assert_response :conflict
    patch app_v1_registration_path, params: { registration: form.merge(phone_number: "12") }, headers:, as: :json
    assert_response :unprocessable_entity
    assert_match "10 số", response.parsed_body.dig("errors", "phone_number").sole
    patch app_v1_registration_path, params: { registration: form.merge(maps_url: "maps.app.goo.gl/x") }, headers:, as: :json
    assert_equal "https://maps.app.goo.gl/x", request.reload.maps_url

    post app_v1_session_path, params: { access_token: "zmp-new" }, as: :json
    assert_equal "pending", response.parsed_body.dig("registration", "status")

    assert request.approve!(by: users(:admin))
    get app_v1_registration_path, headers:, as: :json
    assert_response :conflict
    assert_equal "registered", response.parsed_body["error"]
    post app_v1_session_path, params: { access_token: "zmp-new" }, as: :json
    assert_response :created

    get app_v1_registration_path, headers: { "X-Registration-Token" => "forged" }, as: :json
    assert_response :unauthorized
    travel 31.minutes
    get app_v1_registration_path, headers:, as: :json
    assert_response :unauthorized
  end
end
