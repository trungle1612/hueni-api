# Đặt phòng theo đoàn (#164): several rooms, one contact. Each room is a normal booking tagged with group_id.
# bill one = the leader pays every room except those marked pays_own (Khách tự trả); split = each room its own folio.
class CreateGroups < ActiveRecord::Migration[8.1]
  def change
    create_table :groups do |t|
      t.references :place, null: false, foreign_key: true
      t.integer :number, null: false
      t.string :name, null: false
      t.string :contact
      t.string :phone
      t.string :origin
      t.integer :discount_pct, null: false, default: 0
      t.string :bill, null: false, default: "one"
      t.timestamps
      t.check_constraint "bill IN ('one', 'split')", name: "groups_bill_values"
      t.check_constraint "discount_pct BETWEEN 0 AND 100", name: "groups_discount_pct_range"
    end
    add_index :groups, [ :place_id, :number ], unique: true

    add_column :places, :last_group_number, :integer, null: false, default: 0
    add_reference :bookings, :group, foreign_key: true
    add_column :bookings, :pays_own, :boolean, null: false, default: false
  end
end
