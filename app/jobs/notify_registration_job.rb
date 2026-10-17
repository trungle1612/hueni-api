# Tells the admins' Telegram channel about a new owner registration. Telegram is a third party:
# name, homestay and the admin link only, never the phone number or Zalo id.
# No TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID (development, test) → nothing is sent; the admin badge still shows it.
class NotifyRegistrationJob < ApplicationJob
  class Error < StandardError; end

  retry_on Error, Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, attempts: 3

  def perform(registration, admin_url)
    token, chat_id = ENV["TELEGRAM_BOT_TOKEN"].presence, ENV["TELEGRAM_CHAT_ID"].presence
    return unless token && chat_id

    text = "Yêu cầu đăng ký mới: #{registration.name} — #{registration.homestay_name}\n#{admin_url}"
    response = Net::HTTP.post_form(URI("https://api.telegram.org/bot#{token}/sendMessage"), chat_id:, text:)
    raise Error, "Telegram HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
  end
end
