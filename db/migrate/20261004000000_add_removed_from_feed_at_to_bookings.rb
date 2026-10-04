class AddRemovedFromFeedAtToBookings < ActiveRecord::Migration[8.1]
  def change
    add_column :bookings, :removed_from_feed_at, :datetime
  end
end
