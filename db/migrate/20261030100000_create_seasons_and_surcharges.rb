# Giá theo mùa và chính sách (#163): seasons (+% on their nights), Phụ thu theo khách (display only), Ở dài ngày and
# Chính sách huỷ on the place, and each booking's season % per night, fixed when the night is booked.
class CreateSeasonsAndSurcharges < ActiveRecord::Migration[8.1]
  def change
    create_table :seasons do |t|
      t.references :place, null: false, foreign_key: true
      t.string :name, null: false
      t.date :start_date, null: false
      t.date :end_date, null: false
      t.integer :percent, null: false
      t.timestamps
      t.check_constraint "end_date >= start_date", name: "seasons_dates_ordered"
      t.check_constraint "percent > 0", name: "seasons_percent_positive"
    end

    create_table :surcharges do |t|
      t.references :place, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :price, null: false
      t.string :unit
      t.timestamps
      t.check_constraint "price >= 0", name: "surcharges_price_non_negative"
    end
    add_index :surcharges, [ :place_id, :name ], unique: true

    add_column :places, :long_stay, :boolean, null: false, default: false
    add_column :places, :cancel_policy, :string, null: false, default: "flex"
    add_check_constraint :places, "cancel_policy IN ('flex', 'mid', 'strict')", name: "places_cancel_policy"

    add_column :bookings, :season_percents, :json
    add_column :bookings, :long_stay, :boolean, null: false, default: false

    # Every homestay starts with the design's list; owners edit it.
    reversible do |dir|
      dir.up do
        execute <<~SQL
          INSERT INTO surcharges (place_id, name, price, unit, created_at, updated_at)
          SELECT places.id, defaults.name, defaults.price, defaults.unit, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
          FROM places CROSS JOIN (
            SELECT 'Người lớn thêm' AS name, 150000 AS price, 'đêm' AS unit
            UNION ALL SELECT 'Trẻ 6 – 11 tuổi', 75000, 'đêm'
            UNION ALL SELECT 'Trẻ dưới 6 tuổi', 0, NULL
          ) AS defaults
        SQL
      end
    end
  end
end
