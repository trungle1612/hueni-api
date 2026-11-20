# Thông báo hệ thống (#213): Tính năng mới or Bảo trì, written by admins in /admin, shown to every Mini App and PWA user
# for Notification::DAYS from published_at and pushed to their phones once (#262).
# content: "## Heading" starts a block, "- item" / "1. item" are its list.
class Announcement < ApplicationRecord
  KINDS = { "feature" => "Tính năng mới", "maintenance" => "Bảo trì" }.freeze

  validates :kind, inclusion: { in: KINDS.keys }
  validates :title, :summary, :published_at, presence: true
  validates :title, :summary, :cta, length: { maximum: 120 }
  validates :cta_path, format: { with: %r{\A/[\w/\-?=&]*\z}, message: "phải là đường dẫn trong Mini App, bắt đầu bằng /" }, allow_blank: true
  validates :cta_path, presence: { message: "cần có khi có nút" }, if: -> { cta.present? }

  scope :shown, -> { where(published_at: Notification::DAYS.days.ago..Time.current) }

  # Web Push (#262): sent once when Hiện từ arrives; a new Hiện từ before then reschedules it.
  after_commit :schedule_push, on: %i[create update], if: -> { pushed_at.nil? && saved_change_to_published_at? }

  def kicker = kind == "feature" ? "TÍNH NĂNG MỚI · #{published_at.strftime("%d/%m/%Y")}" : "BẢO TRÌ HỆ THỐNG"

  # [{ h:, ordered:, items: [] }]; lines before the first heading go in a block without one.
  def blocks
    content.to_s.lines.map(&:strip).compact_blank.each_with_object([]) do |line, blocks|
      next blocks << { h: line.delete_prefix("## "), ordered: false, items: [] } if line.start_with?("## ")
      blocks << { h: nil, ordered: false, items: [] } if blocks.empty?
      blocks.last[:ordered] = true if line.match?(/\A\d+\.\s/)
      blocks.last[:items] << line.sub(/\A(-|\d+\.)\s*/, "")
    end
  end

  # Owners and staff with a phone turned on, unless they turned off Tính năng mới và bảo trì.
  def recipients
    users = User.where(id: PlaceMembership.unlocked.select(:user_id)).where(id: Session.joins(:push_subscriptions).select(:user_id))
    users.reject { "news".in?(it.notifications_off) }
  end

  # Tapped → its sheet in Thông báo, like a tap in the inbox.
  def push_payload(user)
    { title:, body: summary, tag: "a#{id}", silent: Notification.quiet?(user, "news"),
      url: Rails.application.routes.url_helpers.pms_open_notification_path("a#{id}") }
  end

  def push_options = {}

  # True once, when shown: a job queued for an earlier Hiện từ finds it sent already or not shown yet.
  def claim_push = Announcement.shown.where(id:, pushed_at: nil).update_all(pushed_at: Time.current) == 1

  def detail = { kind:, kicker:, title:, intro: intro.presence, blocks:, note: note.presence, cta: cta.presence, cta_path: cta_path.presence }

  private
    def schedule_push
      PushAnnouncementJob.set(wait_until: published_at).perform_later(self) if WebPush.enabled?
    end
end
