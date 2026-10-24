# Booking code DP-0142 (#124): a per-homestay sequence. Existing bookings are numbered by created_at.
class AddNumberToBookings < ActiveRecord::Migration[8.1]
  def up
    add_column :bookings, :number, :integer
    add_column :places, :last_booking_number, :integer, null: false, default: 0
    execute <<~SQL
      UPDATE bookings SET number = (
        SELECT n FROM (
          SELECT b.id, ROW_NUMBER() OVER (PARTITION BY r.place_id ORDER BY b.created_at, b.id) AS n
          FROM bookings b JOIN rooms r ON r.id = b.room_id
        ) numbered WHERE numbered.id = bookings.id
      )
    SQL
    execute <<~SQL
      UPDATE places SET last_booking_number = COALESCE(
        (SELECT MAX(b.number) FROM bookings b JOIN rooms r ON r.id = b.room_id WHERE r.place_id = places.id), 0)
    SQL
  end

  def down
    remove_column :bookings, :number
    remove_column :places, :last_booking_number
  end
end
