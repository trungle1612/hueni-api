class CreateRoomPhotos < ActiveRecord::Migration[8.1]
  def change
    create_table :room_photos do |t|
      t.references :room, null: false, foreign_key: true
      t.string :key, null: false
      t.integer :position, null: false
      t.timestamps
    end
    add_index :room_photos, :key, unique: true
  end
end
