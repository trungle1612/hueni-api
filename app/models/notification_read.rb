# Thông báo (#213): one notification someone has read, by its Notification key. Older than the inbox → pruned.
class NotificationRead < ApplicationRecord
  belongs_to :user

  # The keys a client may send: at most a page of them, each short.
  def self.keys(param) = Array(param).grep(String).select { it.size <= 40 }.first(500)

  def self.mark(user, keys)
    insert_all(keys.map { { user_id: user.id, key: it, created_at: Time.current } }, unique_by: %i[user_id key], record_timestamps: false) if keys.any?
  end

  def self.prune = where(created_at: ...(Notification::DAYS + 1).days.ago).delete_all
end
