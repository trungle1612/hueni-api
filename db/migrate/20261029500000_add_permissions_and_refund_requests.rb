# Nhân viên (#168, ADR-001 in hueni-workspace): roles stay owner / staff; staff get extra rights per homestay
# (permissions: discount | refund | report; discount on by default = today's behaviour), and can be locked out of one
# homestay. A staff refund without the refund right is a request the owner approves or rejects (Chờ duyệt).
class AddPermissionsAndRefundRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :place_memberships, :permissions, :json, null: false, default: [ "discount" ]
    add_column :place_memberships, :locked_at, :datetime

    create_table :refund_requests do |t|
      t.references :booking, null: false, foreign_key: true
      t.references :requested_by, foreign_key: { to_table: :users }
      t.references :decided_by, foreign_key: { to_table: :users }
      t.references :payment, foreign_key: { on_delete: :nullify } # an owner may delete a wrong refund entry
      t.integer :amount, null: false
      t.string :payment_method, null: false
      t.string :note
      t.string :status, null: false, default: "pending"
      t.datetime :decided_at
      t.timestamps
      t.check_constraint "status IN ('pending', 'approved', 'rejected')", name: "refund_requests_status_values"
      t.check_constraint "amount > 0", name: "refund_requests_amount_positive"
    end
  end
end
