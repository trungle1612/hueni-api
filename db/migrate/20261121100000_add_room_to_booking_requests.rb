# Trang đặt phòng (#290): the room the guest picked on hue-ni, if any. A deleted room leaves a typed request.
class AddRoomToBookingRequests < ActiveRecord::Migration[8.1]
  def change
    add_reference :booking_requests, :room, foreign_key: { on_delete: :nullify }
  end
end
