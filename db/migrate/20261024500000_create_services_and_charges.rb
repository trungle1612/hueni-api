# Folio (#140): each homestay's service catalog, services added to a booking (a snapshot of name, price, unit),
# and Giảm giá on the booking.
class CreateServicesAndCharges < ActiveRecord::Migration[8.1]
  def change
    create_table :services do |t|
      t.references :place, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :price, null: false
      t.string :unit
      t.timestamps
      t.check_constraint "price >= 0", name: "services_price_non_negative"
    end
    add_index :services, [ :place_id, :name ], unique: true

    create_table :booking_charges do |t|
      t.references :booking, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.string :name, null: false
      t.integer :unit_price, null: false
      t.string :unit
      t.integer :quantity, null: false, default: 1
      t.timestamps
      t.check_constraint "unit_price >= 0 AND quantity > 0", name: "booking_charges_amounts"
    end

    add_column :bookings, :discount, :integer
    add_column :bookings, :discount_reason, :string

    # Every homestay starts with the design's catalog; owners edit it.
    reversible do |dir|
      dir.up do
        execute <<~SQL
          INSERT INTO services (place_id, name, price, unit, created_at, updated_at)
          SELECT places.id, defaults.name, defaults.price, defaults.unit, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
          FROM places CROSS JOIN (
            SELECT 'Nước suối' AS name, 15000 AS price, 'chai' AS unit
            UNION ALL SELECT 'Giặt ủi', 30000, 'kg'
            UNION ALL SELECT 'Thuê xe máy', 150000, 'ngày'
            UNION ALL SELECT 'Nhận phòng sớm', 100000, NULL
            UNION ALL SELECT 'Trả phòng muộn', 150000, NULL
          ) AS defaults
        SQL
      end
    end
  end
end
