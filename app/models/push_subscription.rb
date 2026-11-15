# Web Push (#237): a browser that turned on Thông báo trên điện thoại này, under the login (Session) it was turned on
# in: logging out, Khoá tài khoản, a reset login and Xoá tài khoản end the session and so the pushes.
class PushSubscription < ApplicationRecord
  # The browsers' push services (Chrome, Firefox, Safari, Edge). We POST to the endpoint, so nothing else (SSRF).
  HOSTS = /\A(fcm\.googleapis\.com|[\w-]+(\.[\w-]+)*\.(push\.services\.mozilla\.com|push\.apple\.com|notify\.windows\.com))\z/

  belongs_to :session

  validate :valid_endpoint
  validate -> { errors.add(:base, "Khoá mã hoá không hợp lệ.") unless key_size(p256dh) == 65 && key_size(auth) == 16 }

  # This browser now belongs to this login (another account may have used it before).
  def self.save_for(session, endpoint:, p256dh:, auth:)
    find_or_initialize_by(endpoint: endpoint.to_s).tap { it.update(session:, p256dh:, auth:) }
  end

  # Gone at the push service → deleted, nothing raised.
  def deliver(payload, urgency: "normal")
    WebPush.deliver(endpoint, p256dh:, auth:, payload:, urgency:)
  rescue WebPush::Gone
    destroy
  end

  private
    def valid_endpoint
      uri = URI(endpoint.to_s)
      errors.add(:endpoint, "không hợp lệ") unless uri.is_a?(URI::HTTPS) && uri.port == 443 && uri.host.to_s.match?(HOSTS)
    rescue URI::InvalidURIError
      errors.add(:endpoint, "không hợp lệ")
    end

    def key_size(value)
      WebPush.decode(value).bytesize
    rescue ArgumentError
      0
    end
end
