# Thông báo (#216): saved when the event happens (model callbacks), one row per homestay event, instead of
# being re-worded from paper_trail versions on every read (#213). Read marks stay per user (notification_reads).
class CreateStoredNotifications < ActiveRecord::Migration[8.1]
  def change
    create_table :notifications do |t|
      t.references :place, null: false, foreign_key: true, index: false
      t.string :kind, null: false
      t.integer :actor_id
      t.string :source, null: false
      t.string :title, null: false
      t.string :body
      t.integer :booking_id
      t.integer :room_id
      t.integer :refund_request_id
      t.datetime :created_at, null: false
      t.index %i[place_id created_at]
    end
  end
end
