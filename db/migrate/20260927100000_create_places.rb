class CreatePlaces < ActiveRecord::Migration[8.1]
  def change
    create_table :places do |t|
      t.string :slug, null: false
      t.string :name, null: false
      # Read-only copy of hueni's homestay.json, overwritten by places:import.
      t.string :address
      t.string :phone
      t.decimal :rating, precision: 2, scale: 1
      t.decimal :lat, precision: 10, scale: 7
      t.decimal :lng, precision: 10, scale: 7
      t.string :website
      t.string :cover_image_url
      t.string :google_place_id
      t.timestamps
    end
    add_index :places, :slug, unique: true
  end
end
