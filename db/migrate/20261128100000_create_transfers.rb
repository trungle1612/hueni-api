# Đưa đón sân bay (#306): partner homestays offer a Phú Bài pickup / drop inside the booking request. The driver is told
# by hand (no driver account), so the place only keeps the partner flag, the price per leg and the driver's phone.
class CreateTransfers < ActiveRecord::Migration[8.1]
  def change
    change_table :places, bulk: true do |t|
      t.boolean :transfer_partner, null: false, default: false
      t.integer :transfer_price, null: false, default: 200_000
      t.string :driver_phone
    end

    create_table :transfers do |t|
      t.references :place, null: false, foreign_key: true
      t.references :booking_request, foreign_key: { on_delete: :cascade }
      t.references :booking, foreign_key: { on_delete: :nullify }
      t.string :kind, null: false
      t.string :status, null: false, default: "pending"
      t.date :date, null: false
      t.string :pickup_time
      t.string :flight
      t.integer :price, null: false
      t.timestamps
      t.check_constraint "kind IN ('arrival', 'departure')", name: "transfers_kind"
      t.check_constraint "status IN ('pending', 'done', 'cancelled')", name: "transfers_status"
    end
  end
end
