# Web Push (#237): one saved Thông báo to the phones of the members who see it in their inbox (Notification#recipients).
# An expired subscription is deleted; any other failure is reported and the rest still get theirs (no retry: it would
# push twice to those already reached).
class PushNotificationJob < ApplicationJob
  # Pruned or its homestay deleted meanwhile.
  discard_on ActiveJob::DeserializationError

  def perform(notification)
    options = notification.push_options or return
    notification.recipients.each do |user|
      payload = notification.push_payload(user).to_json
      user.push_subscriptions.each do |subscription|
        subscription.deliver(payload, **options)
      rescue StandardError => error
        Rails.error.report(error, handled: true)
      end
    end
  end
end
