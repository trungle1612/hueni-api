# Zalo Mini App webhook (#225), the Webhook URL in mini.zalo.me/developers → Open APIs → Quản lý APIs.
# No token: Zalo signs each event, x-zevent-signature = SHA-256 hex of the payload's values (keys A→Z, objects as JSON) + API Key.
# user.revoke.consent (the user withdrew consent inside Zalo) deletes the account like Xoá tài khoản (#192).
# Other events, other apps and unknown users answer 200 and change nothing: Zalo may retry.
class MiniApp::V1::ZaloWebhooksController < MiniApp::V1::BaseController
  skip_before_action :authenticate
  rate_limit to: 60, within: 1.minute,
    with: -> { render json: { error: "rate_limited", message: "Thử lại sau ít phút." }, status: :too_many_requests }

  def create
    payload = JSON.parse(request.raw_post)
    return head :unauthorized unless payload.is_a?(Hash) && signed?(payload)

    if payload["event"] == "user.revoke.consent" && payload["appId"].to_s == Rails.configuration.x.zalo_app_id.to_s && payload["userId"].present?
      zalo_id = payload["userId"].to_s
      User.find_by(zalo_id:)&.delete_account!
      RegistrationRequest.where(zalo_id:).delete_all
    end
    head :ok
  rescue JSON::ParserError
    head :unauthorized
  end

  private
    def signed?(payload)
      api_key = Rails.configuration.x.zalo_api_key
      return false if api_key.blank?
      values = payload.sort.map { |_key, value| value.is_a?(Hash) || value.is_a?(Array) ? value.to_json : value.to_s }
      ActiveSupport::SecurityUtils.secure_compare(Digest::SHA256.hexdigest(values.join + api_key), request.headers["x-zevent-signature"].to_s)
    end
end
