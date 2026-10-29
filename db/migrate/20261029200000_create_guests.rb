# Hồ sơ khách (#165): what the front desk keeps about a guest of one homestay. The guest is identified by the phone
# digits of their bookings, else the folded name (Guest.key_for); a row exists only once a note or flag is saved.
class CreateGuests < ActiveRecord::Migration[8.1]
  def change
    create_table :guests do |t|
      t.references :place, null: false, foreign_key: true
      t.string :key, null: false
      t.string :name
      t.text :note
      t.string :flag
      t.timestamps
    end
    add_index :guests, [ :place_id, :key ], unique: true
  end
end
