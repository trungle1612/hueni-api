# Mã mời (#211): a code that signs an unknown Zalo account into a homestay with a role. Owners make staff codes
# for their homestay; admins make any code (Zalo review: an owner code for the demo homestay).
class CreateInvites < ActiveRecord::Migration[8.1]
  def change
    create_table :invites do |t|
      t.references :place, null: false, foreign_key: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.string :code, null: false, index: { unique: true }
      t.string :role, null: false, default: "staff"
      t.integer :max_uses, null: false, default: 1
      t.integer :uses_count, null: false, default: 0
      t.datetime :expires_at, null: false
      t.timestamps
      t.check_constraint "role IN ('owner', 'staff')", name: "invites_role_values"
    end
  end
end
