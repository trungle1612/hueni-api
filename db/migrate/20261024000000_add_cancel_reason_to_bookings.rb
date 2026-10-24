class AddCancelReasonToBookings < ActiveRecord::Migration[8.1]
  def change
    add_column :bookings, :cancel_reason, :string
  end
end
