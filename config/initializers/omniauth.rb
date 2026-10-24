# Zalo login (#97): owners and staff log in only this way, admins also with phone + password.
# Zalo app (developers.zalo.me) callback URL: https://api.hueni.me/auth/zalo2/callback
# Keys: env (Kamal secrets in production) or encrypted credentials `zalo: { app_id:, app_secret: }`,
# so development uses the real Zalo app too.
zalo_app_id = ENV["ZALO_APP_ID"].presence || Rails.application.credentials.dig(:zalo, :app_id)
zalo_app_secret = ENV["ZALO_APP_SECRET"].presence || Rails.application.credentials.dig(:zalo, :app_secret)

# Without keys the login page says so instead of offering a button that can't work.
Rails.configuration.x.zalo_configured = zalo_app_id.present? && zalo_app_secret.present?
# The Mini App API checks access tokens with the same app (#152).
Rails.configuration.x.zalo_app_secret = zalo_app_secret

Rails.application.config.middleware.use OmniAuth::Builder do
  provider :zalo2, zalo_app_id, zalo_app_secret
end

# omniauth-zalo2 0.2.0 raises NoMethodError (a 500) when the Graph response has no picture, e.g. an
# error JSON. Its blank uid then reaches ZaloSessionsController, which rejects it.
OmniAuth::Strategies::Zalo2.info { { "name" => raw_info["name"], "picture" => raw_info.dig("picture", "data", "url") } }

OmniAuth.config.logger = Rails.logger

# Real Zalo in development needs http://localhost:3000/auth/zalo2/callback in the Zalo app.
if Rails.env.development? && ENV["ZALO_FAKE"].present?
  # Opt-in fake Zalo (ZALO_FAKE=1 bin/dev): the Zalo button logs in as the Zalo id picked next to it.
  OmniAuth.config.test_mode = true
  OmniAuth.config.before_request_phase = ->(env) do
    OmniAuth.config.mock_auth[:zalo2] = OmniAuth::AuthHash.new(provider: "zalo2", uid: Rack::Request.new(env).params["dev_zalo_id"].to_s)
  end
end
