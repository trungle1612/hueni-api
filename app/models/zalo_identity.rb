# Who is behind a Zalo Mini App access token (zmp-sdk getAccessToken, #152), asked from Zalo's Graph API.
# appsecret_proof (HMAC-SHA256 of the token with our app secret) makes Zalo refuse a token issued to another app.
# Every method returns nil when Zalo says no, is unreachable, or we have no app secret.
module ZaloIdentity
  ME = URI("https://graph.zalo.me/v2.0/me?fields=id,name")
  PHONE = URI("https://graph.zalo.me/v2.0/me/info")

  # { id:, name: }
  def self.me(access_token)
    secret = Rails.configuration.x.zalo_app_secret
    return if access_token.blank? || secret.blank?
    body = get(ME, "access_token" => access_token, "appsecret_proof" => OpenSSL::HMAC.hexdigest("SHA256", secret, access_token))
    { id: body["id"].to_s, name: body["name"].to_s } if body&.dig("id").present?
  end

  # The Zalo account's phone (84…), from the code of zmp-sdk getPhoneNumber() (the user allowed it), for #98 linking.
  def self.phone(access_token, code)
    secret = Rails.configuration.x.zalo_app_secret
    return if access_token.blank? || code.blank? || secret.blank?
    get(PHONE, "access_token" => access_token, "code" => code, "secret_key" => secret)&.dig("data", "number").presence
  end

  def self.get(uri, headers)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 5) { it.request(Net::HTTP::Get.new(uri, headers)) }
    JSON.parse(response.body) if response.is_a?(Net::HTTPSuccess)
  rescue JSON::ParserError, Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, OpenSSL::SSL::SSLError => error
    Rails.logger.warn("Zalo #{uri.path} failed: #{error.class}")
    nil
  end
  private_class_method :get
end
