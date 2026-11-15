# Web Push (#237) with stdlib OpenSSL / Net::HTTP: the payload encrypted for one browser (RFC 8291, aes128gcm) and
# signed for its push service with our VAPID key (RFC 8292). The key: env VAPID_KEY = base64 DER of a P-256 key
# (`bin/rails push:key` makes one); without it nothing is pushed and the PWA hides the switch.
module WebPush
  CURVE = "prime256v1".freeze
  SUBJECT = "https://hueni.me".freeze
  # The browser's subscription is gone (unsubscribed, expired): delete it.
  Gone = Class.new(StandardError)
  Error = Class.new(StandardError)

  class << self
    attr_writer :key

    def key = defined?(@key) ? @key : (@key = ENV["VAPID_KEY"].presence&.then { OpenSSL::PKey::EC.new(Base64.decode64(it)) })
    def enabled? = key.present?

    # applicationServerKey for pushManager.subscribe: the raw public point, base64url.
    def public_key = encode(key.public_key.to_bn.to_s(2))

    def deliver(endpoint, p256dh:, auth:, payload:, urgency: "normal", ttl: 1.day.to_i)
      uri = URI(endpoint)
      request = Net::HTTP::Post.new(uri, "Content-Encoding" => "aes128gcm", "Content-Type" => "application/octet-stream",
        "TTL" => ttl.to_s, "Urgency" => urgency, "Authorization" => vapid(uri))
      request.body = encrypt(payload, decode(p256dh), decode(auth))
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) { it.request(request) }
      raise Gone if response.code.in?(%w[404 410])
      raise Error, "push #{response.code}: #{response.body.to_s.first(200)}" unless response.is_a?(Net::HTTPSuccess)
    end

    # One aes128gcm record: salt · record size · our ephemeral public key · ciphertext. salt / as_key: for the RFC's test vector.
    def encrypt(payload, ua_public, auth_secret, salt: SecureRandom.random_bytes(16), as_key: OpenSSL::PKey::EC.generate(CURVE))
      shared = as_key.dh_compute_key(OpenSSL::PKey::EC::Point.new(as_key.group, OpenSSL::BN.new(ua_public, 2)))
      as_public = as_key.public_key.to_bn.to_s(2)
      ikm = hmac(hmac(auth_secret, shared), "WebPush: info\0".b + ua_public + as_public + "\x01".b)
      prk = hmac(salt, ikm)
      cipher = OpenSSL::Cipher.new("aes-128-gcm").encrypt
      cipher.key = hmac(prk, "Content-Encoding: aes128gcm\0\x01".b).first(16)
      cipher.iv = hmac(prk, "Content-Encoding: nonce\0\x01".b).first(12)
      body = cipher.update(payload.b + "\x02".b) + cipher.final + cipher.auth_tag
      salt + [ 4096, as_public.bytesize ].pack("NC") + as_public + body
    end

    def decode(value) = Base64.urlsafe_decode64(value.to_s)
    def encode(bytes) = Base64.urlsafe_encode64(bytes, padding: false)

    private
      def hmac(key, data) = OpenSSL::HMAC.digest("SHA256", key, data)

      # ES256 JWT for the push service's origin; the DER signature becomes raw r · s.
      def vapid(uri)
        input = [ { typ: "JWT", alg: "ES256" }, { aud: "https://#{uri.host}", exp: 12.hours.from_now.to_i, sub: SUBJECT } ].map { encode(it.to_json) }.join(".")
        signature = OpenSSL::ASN1.decode(key.sign("SHA256", input)).value.map { it.value.to_s(2).rjust(32, "\0".b) }.join
        "vapid t=#{input}.#{encode(signature)}, k=#{public_key}"
      end
  end
end
