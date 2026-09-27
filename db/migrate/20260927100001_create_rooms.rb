class CreateRooms < ActiveRecord::Migration[8.1]
  def change
    create_table :rooms do |t|
      t.references :place, null: false, foreign_key: true, index: false
      t.string :name, null: false
      t.integer :max_guests, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :rooms, [ :place_id, :name ], unique: true
  end
end
