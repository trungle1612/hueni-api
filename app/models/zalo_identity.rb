# The Zalo user id behind a Mini App access token (zmp-sdk getAccessToken, #152), asked from Zalo's Graph API.
# appsecret_proof (HMAC-SHA256 of the token with our app secret) makes Zalo refuse a token issued to another app.
# nil when Zalo says no, is unreachable, or we have no app secret.
module ZaloIdentity
  ME = URI("https://graph.zalo.me/v2.0/me?fields=id,name")

  def self.id_for(access_token)
    secret = Rails.configuration.x.zalo_app_secret
    return if access_token.blank? || secret.blank?
    request = Net::HTTP::Get.new(ME, "access_token" => access_token, "appsecret_proof" => OpenSSL::HMAC.hexdigest("SHA256", secret, access_token))
    response = Net::HTTP.start(ME.host, ME.port, use_ssl: true, open_timeout: 5, read_timeout: 5) { it.request(request) }
    JSON.parse(response.body)["id"].to_s.presence if response.is_a?(Net::HTTPSuccess)
  rescue JSON::ParserError, Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, OpenSSL::SSL::SSLError => error
    Rails.logger.warn("Zalo /me failed: #{error.class}")
    nil
  end
end
