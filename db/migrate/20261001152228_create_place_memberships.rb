class CreatePlaceMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :place_memberships do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.references :place, null: false, foreign_key: true
      t.timestamps
    end
    add_index :place_memberships, [ :user_id, :place_id ], unique: true
  end
end
