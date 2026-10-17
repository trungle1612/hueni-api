# Zalo login (#97): owners and staff log in only this way, admins also with phone + password.
# Zalo app (developers.zalo.me) callback URL: https://api.hueni.me/auth/zalo2/callback
Rails.application.config.middleware.use OmniAuth::Builder do
  provider :zalo2, ENV["ZALO_APP_ID"], ENV["ZALO_APP_SECRET"]
end

# omniauth-zalo2 0.2.0 raises NoMethodError (a 500) when the Graph response has no picture, e.g. an
# error JSON. Its blank uid then reaches ZaloSessionsController, which rejects it.
OmniAuth::Strategies::Zalo2.info { { "name" => raw_info["name"], "picture" => raw_info.dig("picture", "data", "url") } }

OmniAuth.config.logger = Rails.logger

if Rails.env.development?
  # No real Zalo app in development: the Zalo button logs in as the Zalo id picked next to it.
  OmniAuth.config.test_mode = true
  OmniAuth.config.before_request_phase = ->(env) do
    OmniAuth.config.mock_auth[:zalo2] = OmniAuth::AuthHash.new(provider: "zalo2", uid: Rack::Request.new(env).params["dev_zalo_id"].to_s)
  end
end
