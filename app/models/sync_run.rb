# One CalendarFeed#sync: when, how long, what it changed or why it failed. Admin-only log (#92), kept RETENTION.
class SyncRun < ApplicationRecord
  RETENTION = 30.days
  TRIGGER_LABELS = { "hourly" => "Mỗi giờ", "manual" => "Đồng bộ ngay", "added" => "Thêm kênh" }.freeze

  belongs_to :calendar_feed

  enum :trigger, { hourly: "hourly", manual: "manual", added: "added" }, validate: true

  # Daily from config/recurring.yml.
  def self.prune = where(started_at: ...RETENTION.ago).delete_all

  def trigger_label = TRIGGER_LABELS.fetch(trigger)
  def duration = finished_at - started_at
  def changes? = (created_count + updated_count + removed_count).positive?
end
