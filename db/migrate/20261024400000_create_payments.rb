# Payments (#139): money in (payment) and out (refund) per booking. Đã cọc becomes the first payment.
# The homestay's bank account is shown when the guest pays by Chuyển khoản.
class CreatePayments < ActiveRecord::Migration[8.1]
  def up
    create_table :payments do |t|
      t.references :booking, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.integer :amount, null: false
      t.string :kind, null: false, default: "payment"
      t.string :payment_method, null: false
      t.string :note
      t.timestamps
      t.check_constraint "amount > 0", name: "payments_amount_positive"
      t.check_constraint "kind IN ('payment', 'refund')", name: "payments_kind_values"
      t.check_constraint "payment_method IN ('cash', 'bank', 'card')", name: "payments_payment_method_values"
    end
    execute <<~SQL
      INSERT INTO payments (booking_id, amount, kind, payment_method, note, created_at, updated_at)
      SELECT id, deposit, 'payment', 'cash', 'Cọc', created_at, created_at FROM bookings WHERE deposit > 0
    SQL
    remove_column :bookings, :deposit

    add_column :places, :bank_name, :string
    add_column :places, :bank_account, :string
    add_column :places, :bank_holder, :string
  end

  def down
    remove_column :places, :bank_holder
    remove_column :places, :bank_account
    remove_column :places, :bank_name
    add_column :bookings, :deposit, :integer
    execute <<~SQL
      UPDATE bookings SET deposit = (SELECT SUM(CASE kind WHEN 'refund' THEN -amount ELSE amount END) FROM payments WHERE booking_id = bookings.id)
    SQL
    drop_table :payments
  end
end
