# Giao ca (#167): one till per homestay. A shift is everything since the previous close: expected cash = what that
# close left in the till (keep) + cash payments − cash refunds − cash expenses since. Closing records the count.
class CreateCashExpensesAndShiftCloses < ActiveRecord::Migration[8.1]
  def change
    create_table :cash_expenses do |t|
      t.references :place, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.integer :amount, null: false
      t.string :reason, null: false
      t.timestamps
      t.check_constraint "amount > 0", name: "cash_expenses_amount_positive"
    end

    create_table :shift_closes do |t|
      t.references :place, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.references :handed_to, foreign_key: { to_table: :users }
      t.integer :opening, null: false
      t.integer :expected, null: false
      t.integer :counted, null: false
      t.json :denominations
      t.integer :keep, null: false
      t.string :note
      t.timestamps
      t.check_constraint "counted >= 0 AND keep >= 0 AND keep <= counted", name: "shift_closes_amounts"
    end
    add_index :shift_closes, [ :place_id, :created_at ]
  end
end
