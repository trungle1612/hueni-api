class Admin::PlacesController < Admin::BaseController
  def show
    @place = Current.user.accessible_places.find_by!(slug: params[:slug])
    @rooms = @place.rooms.order(:name)
    @statuses = today_statuses(@rooms)
  end

  private
    # room_id => "confirmed" | "hold"; confirmed wins when a room has both today.
    def today_statuses(rooms)
      Booking.blocking_on(Date.current).where(room_id: rooms.map(&:id)).pluck(:room_id, :status)
        .each_with_object({}) { |(room_id, status), statuses| statuses[room_id] = status unless statuses[room_id] == "confirmed" }
    end
end
