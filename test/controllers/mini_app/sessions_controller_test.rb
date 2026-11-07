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
    post api_v1_session_path, params: { access_token: "zmp-token" }, as: :json
    assert_response :created
    token = response.parsed_body["token"]
    assert_equal 32, token.size
    assert_equal({ "id" => places(:tomo).id, "slug" => "tomo-homestay", "name" => places(:tomo).name, "role" => "owner", "permissions" => %w[discount refund report] }, response.parsed_body["places"].sole)
    assert_not ApiToken.exists?(token_digest: token) # only the digest is kept
    assert_equal "*", response.headers["Access-Control-Allow-Origin"]

    get api_v1_me_path, headers: bearer(token)
    assert_response :success
    assert_equal users(:owner).name, response.parsed_body.dig("user", "name")

    delete api_v1_session_path, headers: bearer(token)
    assert_response :no_content
    get api_v1_me_path, headers: bearer(token)
    assert_response :unauthorized
    assert_equal "unauthorized", response.parsed_body["error"]
  end

  test "a token Zalo refuses (or another app's) is rejected" do
    zalo_me("bad", { error: 452, message: "Invalid access token" })
    post api_v1_session_path, params: { access_token: "bad" }, as: :json
    assert_response :unauthorized
    assert_equal "zalo_rejected", response.parsed_body["error"]

    post api_v1_session_path, params: { access_token: "" }, as: :json
    assert_response :unauthorized
    assert_equal 0, ApiToken.count
  end

  test "tokens last 30 days from the last use; reset_login revokes them; no token, no access" do
    token = users(:owner).api_tokens.create!.token
    travel 29.days
    get api_v1_me_path, headers: bearer(token)
    assert_response :success # renewed: 30 more days
    travel 29.days
    get api_v1_me_path, headers: bearer(token)
    assert_response :success
    travel 31.days
    get api_v1_me_path, headers: bearer(token)
    assert_response :unauthorized

    token = users(:owner).api_tokens.create!.token
    users(:owner).reset_login!
    get api_v1_me_path, headers: bearer(token)
    assert_response :unauthorized
    get api_v1_me_path
    assert_response :unauthorized
  end

  test "a linked user accepts the terms (again) for themselves only; GET /me returns the version (#206)" do
    token = users(:owner).api_tokens.create!.token
    get api_v1_me_path, headers: bearer(token)
    assert_nil response.parsed_body.dig("user", "terms_version")

    post terms_api_v1_me_path, params: { version: "" }, headers: bearer(token), as: :json
    assert_response :unprocessable_entity
    assert_equal "terms_required", response.parsed_body["error"]
    post terms_api_v1_me_path, params: { version: "x" * 21 }, headers: bearer(token), as: :json
    assert_response :unprocessable_entity
    assert_equal "invalid", response.parsed_body["error"]

    post terms_api_v1_me_path, params: { version: "2026-11-04", user_id: users(:admin).id }, headers: bearer(token), as: :json
    assert_response :no_content
    assert_equal "2026-11-04", users(:owner).reload.terms_version
    assert users(:owner).terms_accepted_at
    assert_nil users(:admin).reload.terms_version
    get api_v1_me_path, headers: bearer(token)
    assert_equal "2026-11-04", response.parsed_body.dig("user", "terms_version")

    post terms_api_v1_me_path, params: { version: "2026-11-04" }, as: :json
    assert_response :unauthorized
  end

  test "Xoá tài khoản (#192): only my own; logins, Zalo link and memberships go; the homestay keeps its bookings and Hoạt động" do
    staff = User.create!(name: "Bé Na", phone_number: "0987654321", password: "password123", zalo_id: "zalo-na", terms_version: "2026-11-04")
    places(:tomo).place_memberships.create!(user: staff, role: "staff")
    booking = bookings(:limdim_confirmed)
    PaperTrail.request(whodunnit: staff.id.to_s) { booking.update!(note: "Khách đến muộn") }
    payment = booking.payments.create!(amount: 100_000, payment_method: "cash", kind: "payment", user: staff)
    token = staff.api_tokens.create!.token
    owner_token = users(:owner).api_tokens.create!.token

    delete api_v1_me_path, params: { user_id: users(:owner).id }, headers: bearer(token), as: :json
    assert_response :no_content
    get api_v1_me_path, headers: bearer(token)
    assert_response :unauthorized

    staff.reload
    assert_equal [ User::DELETED_NAME, nil, nil, nil ], staff.values_at(:name, :phone_number, :zalo_id, :terms_version)
    assert staff.deleted?
    assert_empty staff.place_memberships
    assert_equal users(:owner).name, users(:owner).reload.name # never anyone else

    zalo_me("zmp-na", { id: "zalo-na", name: "Na" })
    post api_v1_session_path, params: { access_token: "zmp-na" }, as: :json
    assert_equal "not_registered", response.parsed_body["error"]

    assert booking.reload.persisted?
    assert_equal staff, payment.reload.user
    get activity_api_v1_place_path(places(:tomo)), headers: bearer(owner_token)
    assert_response :success
    assert_includes response.parsed_body["activities"].map { it["actor"] }, User::DELETED_NAME
  end

  test "Xoá tài khoản (#192): the last owner takes the bookings and the staff with them; the homestay and its rooms stay" do
    staff = User.create!(name: "Bé Na", phone_number: "0987654321", password: "password123")
    places(:tomo).place_memberships.create!(user: staff, role: "staff")
    booking = bookings(:limdim_confirmed)
    booking.payments.create!(amount: 100_000, payment_method: "cash", kind: "payment")
    places(:hiuhill).place_memberships.create!(user: staff, role: "owner")
    places(:hiuhill).place_memberships.create!(user: users(:owner), role: "owner")

    delete api_v1_me_path, headers: bearer(users(:owner).api_tokens.create!.token)
    assert_response :no_content

    assert_not Booking.exists?(booking.id)
    assert_empty Payment.where(booking_id: booking.id)
    assert_empty PaperTrail::Version.where(item_type: "Booking", item_id: booking.id)
    assert_empty places(:tomo).place_memberships.reload
    assert_equal 2, places(:tomo).rooms.count
    assert_equal [ staff ], places(:hiuhill).users.reload # not the last owner there: only the membership goes
  end

  test "CORS preflight answers without a token" do
    process :options, "/api/v1/me", headers: { "Origin" => "https://h5.zdn.vn", "Access-Control-Request-Method" => "GET" }
    assert_response :no_content
    assert_equal "Authorization, Content-Type, X-Registration-Token", response.headers["Access-Control-Allow-Headers"]
  end

  test "like the web: the Zalo phone links an owner or staff member without Zalo (#98), never an admin" do
    staff = User.create!(name: "Bé Na", phone_number: "0987654321", password: "password123")
    zalo_me("zmp-na", { id: "zalo-na", name: "Na" })
    stub_request(:get, "https://graph.zalo.me/v2.0/me/info")
      .with(headers: { "access_token" => "zmp-na", "code" => "phone-code", "secret_key" => "test-secret" })
      .to_return(body: { data: { number: "84987654321" }, error: 0 }.to_json)
    post api_v1_session_path, params: { access_token: "zmp-na", phone_token: "phone-code" }, as: :json
    assert_response :unprocessable_entity
    assert_equal "terms_required", response.parsed_body["error"]
    assert_nil staff.reload.zalo_id

    travel_to Time.zone.local(2026, 11, 5, 9, 30) do
      post api_v1_session_path, params: { access_token: "zmp-na", phone_token: "phone-code", terms_version: "2026-11-04" }, as: :json
    end
    assert_response :created
    assert_equal "2026-11-04", response.parsed_body.dig("user", "terms_version")
    assert_equal [ "zalo-na", "2026-11-04", Time.zone.local(2026, 11, 5, 9, 30) ], staff.reload.values_at(:zalo_id, :terms_version, :terms_accepted_at)

    users(:admin).update!(phone_number: "0911222333")
    zalo_me("zmp-x", { id: "zalo-x", name: "X" })
    stub_request(:get, "https://graph.zalo.me/v2.0/me/info").with(headers: { "code" => "admin-code" })
      .to_return(body: { data: { number: "84911222333" } }.to_json)
    post api_v1_session_path, params: { access_token: "zmp-x", phone_token: "admin-code", terms_version: "2026-11-04" }, as: :json
    assert_response :forbidden
    assert_nil users(:admin).reload.zalo_id
  end

  test "like /dang-ky: an unknown Zalo registers with the registration token, corrects it while pending, signs in once approved" do
    place = Place.create!(slug: "nha-hanh", name: "Nhà Hạnh", phone: "0234111222") # no owner yet
    zalo_me("zmp-new", { id: "zalo-new", name: "Chị Hạnh" })
    post api_v1_session_path, params: { access_token: "zmp-new" }, as: :json
    assert_response :forbidden
    assert_equal [ "not_registered", nil ], response.parsed_body.values_at("error", "registration")
    headers = { "X-Registration-Token" => response.parsed_body["registration_token"] }

    form = { name: "Chị Hạnh", phone_number: "0933 111 222", place_name: "Nhà Hạnh", maps_url: "" }
    post api_v1_registration_path, params: { registration: form }, headers:, as: :json
    assert_response :unprocessable_entity
    assert_equal "terms_required", response.parsed_body["error"]
    assert_equal 0, RegistrationRequest.count

    form[:terms_version] = "2026-11-04"
    assert_enqueued_jobs 1, only: NotifyRegistrationJob do
      post api_v1_registration_path, params: { registration: form }, headers:, as: :json
    end
    assert_response :created
    request = RegistrationRequest.sole
    assert_equal [ "zalo-new", "Chị Hạnh", place, "0933111222" ], [ request.zalo_id, request.zalo_name, request.place, request.phone_number ]
    assert_equal "pending", response.parsed_body.dig("registration", "status")
    assert_equal "2026-11-04", request.terms_version
    assert request.terms_accepted_at

    post api_v1_registration_path, params: { registration: form }, headers:, as: :json
    assert_response :conflict
    patch api_v1_registration_path, params: { registration: form.except(:terms_version).merge(name: "Hạnh") }, headers:, as: :json
    assert_response :unprocessable_entity
    assert_equal "Chị Hạnh", request.reload.name
    patch api_v1_registration_path, params: { registration: form.merge(phone_number: "12") }, headers:, as: :json
    assert_response :unprocessable_entity
    assert_match "10 số", response.parsed_body.dig("errors", "phone_number").sole
    patch api_v1_registration_path, params: { registration: form.merge(maps_url: "maps.app.goo.gl/x") }, headers:, as: :json
    assert_equal "https://maps.app.goo.gl/x", request.reload.maps_url

    post api_v1_session_path, params: { access_token: "zmp-new" }, as: :json
    assert_equal "pending", response.parsed_body.dig("registration", "status")

    assert request.approve!(by: users(:admin))
    get api_v1_registration_path, headers:, as: :json
    assert_response :conflict
    assert_equal "registered", response.parsed_body["error"]
    post api_v1_session_path, params: { access_token: "zmp-new" }, as: :json
    assert_response :created
    assert_equal "2026-11-04", response.parsed_body.dig("user", "terms_version") # copied on approval

    get api_v1_registration_path, headers: { "X-Registration-Token" => "forged" }, as: :json
    assert_response :unauthorized
    travel 31.minutes
    get api_v1_registration_path, headers:, as: :json
    assert_response :unauthorized
  end
end
