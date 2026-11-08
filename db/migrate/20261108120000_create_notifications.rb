# Thông báo (#213): the inbox is built from what is already recorded (Notification); only who read what, the
# types each user turned off and hueni's announcements are stored.
class CreateNotifications < ActiveRecord::Migration[8.1]
  def change
    create_table :notification_reads do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.string :key, null: false
      t.datetime :created_at, null: false
      t.index %i[user_id key], unique: true
    end

    add_column :users, :notifications_off, :json, null: false, default: [ "room" ]

    create_table :announcements do |t|
      t.string :kind, null: false, default: "feature"
      t.string :title, null: false
      t.string :summary, null: false
      t.text :intro
      t.text :content
      t.text :note
      t.string :cta
      t.string :cta_path
      t.datetime :published_at, null: false, index: true
      t.timestamps
      t.check_constraint "kind IN ('feature', 'maintenance')", name: "announcements_kind_values"
    end
  end
end
