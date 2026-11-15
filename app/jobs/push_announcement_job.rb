# Web Push (#262): a Thông báo hệ thống to every phone that turned push on, once, when its Hiện từ arrives.
class PushAnnouncementJob < PushNotificationJob
  def perform(announcement)
    super if announcement.claim_push
  end
end
