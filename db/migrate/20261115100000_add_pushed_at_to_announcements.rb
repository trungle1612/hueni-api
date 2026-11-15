# Web Push (#262): when an announcement was pushed to phones, so it goes once.
class AddPushedAtToAnnouncements < ActiveRecord::Migration[8.1]
  def change
    add_column :announcements, :pushed_at, :datetime
  end
end
