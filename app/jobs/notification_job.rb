# Thông báo (#216): saves one notification off the request. The model words it when the event happens (who did it,
# the booking as it was: a job has no Current.user and a destroyed booking is gone) and it is enqueued only once the
# event's transaction commits, so a refused action enqueues nothing. The queue is its own database in production.
class NotificationJob < ApplicationJob
  self.enqueue_after_transaction_commit = true
  # The homestay was deleted meanwhile: nobody left to tell.
  discard_on ActiveRecord::InvalidForeignKey

  def perform(attributes) = Notification.create!(attributes)
end
