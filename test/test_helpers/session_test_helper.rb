module SessionTestHelper
  # Logs in through the mocked Zalo login (#97), linking a Zalo id first if the user has none.
  def log_in(user)
    user.update!(zalo_id: "zalo-#{user.id}") unless user.zalo_id
    mock_zalo user.zalo_id
    post "/auth/zalo2"
    follow_redirect!
  end

  def mock_zalo(uid)
    OmniAuth.config.mock_auth[:zalo2] = OmniAuth::AuthHash.new(provider: "zalo2", uid:)
  end

  def sign_in_as(user)
    Current.session = user.sessions.create!

    ActionDispatch::TestRequest.create.cookie_jar.tap do |cookie_jar|
      cookie_jar.signed[:session_id] = Current.session.id
      cookies["session_id"] = cookie_jar[:session_id]
    end
  end

  def sign_out
    Current.session&.destroy!
    cookies.delete("session_id")
  end
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  include SessionTestHelper
end
