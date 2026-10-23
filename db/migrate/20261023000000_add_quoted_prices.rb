class AddQuotedPrices < ActiveRecord::Migration[8.1]
  def change
    add_column :rooms, :weekend_price, :integer
    add_column :bookings, :price, :integer
    add_column :bookings, :weekend_price, :integer
    add_column :bookings, :deposit, :integer

    # Existing bookings were quoted the room's current price.
    reversible do |dir|
      dir.up { execute "UPDATE bookings SET price = (SELECT price FROM rooms WHERE rooms.id = bookings.room_id)" }
    end
  end
end
