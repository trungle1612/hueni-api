class CreateRegistrationRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :registration_requests do |t|
      t.string :zalo_id, null: false
      t.string :zalo_name
      t.string :name, null: false
      t.string :phone_number, null: false
      t.references :place, foreign_key: true
      t.string :place_name, null: false
      t.string :maps_url
      t.string :status, null: false, default: "pending"
      t.text :admin_note
      t.references :decided_by, foreign_key: { to_table: :users }
      t.datetime :decided_at
      t.references :user, foreign_key: true
      t.timestamps

      t.index :zalo_id, unique: true, where: "status = 'pending'", name: "index_registration_requests_one_pending_per_zalo"
      t.check_constraint "status IN ('pending', 'approved', 'rejected')", name: "registration_requests_status_values"
    end
  end
end
