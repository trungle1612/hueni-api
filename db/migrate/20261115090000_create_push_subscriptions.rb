# Web Push (#237): one browser that turned on Thông báo, tied to the login it was turned on in, so logging out,
# Khoá tài khoản, a reset login or Xoá tài khoản (all end the session) stop the pushes too. users.quiet_hours =
# Giờ yên lặng 22:00 – 06:00 (silent pushes except Trùng phòng và lỗi kênh).
class CreatePushSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :push_subscriptions do |t|
      t.references :session, null: false, foreign_key: { on_delete: :cascade }
      t.string :endpoint, null: false, index: { unique: true }
      t.string :p256dh, null: false
      t.string :auth, null: false
      t.timestamps
    end
    add_column :users, :quiet_hours, :boolean, default: true, null: false
  end
end
