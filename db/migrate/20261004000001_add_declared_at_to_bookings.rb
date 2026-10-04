class AddDeclaredAtToBookings < ActiveRecord::Migration[8.1]
  def change
    add_column :bookings, :declared_at, :datetime
  end
end
