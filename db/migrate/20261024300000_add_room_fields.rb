# Room fields (#138): Tầng, Loại phòng (a list per homestay), tiện nghi, ghi chú nội bộ.
class AddRoomFields < ActiveRecord::Migration[8.1]
  def change
    create_table :room_types do |t|
      t.references :place, null: false, foreign_key: true
      t.string :name, null: false
      t.timestamps
    end
    add_index :room_types, [ :place_id, :name ], unique: true

    add_reference :rooms, :room_type, foreign_key: true
    add_column :rooms, :floor, :integer
    add_column :rooms, :amenities, :json, null: false, default: []
    add_column :rooms, :note, :text
  end
end
