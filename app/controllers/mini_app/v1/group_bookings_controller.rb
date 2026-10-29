# A group's rooms (#164): + Thêm phòng, and per room: đổi phòng, Tính vào đoàn / Khách tự trả (pays_own).
class MiniApp::V1::GroupBookingsController < MiniApp::V1::BaseController
  before_action do
    @group = Group.where(place: Current.user.accessible_places).find(params[:group_id])
    @place = @group.place
    authorize!(:operate, @place)
  end

  # { room_id:, start_date:, end_date: } at the group price.
  def create
    room = @place.rooms.find(params.expect(:room_id))
    @group.add_room(room, start_date: date_param(:start_date), end_date: date_param(:end_date)) ? render_group(status: :created) : render_invalid(@group)
  end

  # { booking: { room_id?, pays_own? } }. A guest already in moves like Đổi phòng (old room → dirty);
  # before arrival the booking just changes room, with the same overlap rules as saving it.
  def update
    booking = @group.bookings.manual.confirmed.find(params[:id])
    changes = params.expect(booking: %i[room_id pays_own])
    room = @place.rooms.find(changes[:room_id]) if changes[:room_id]
    if room && booking.checked_out_at
      booking.errors.add(:base, "Khách đã trả phòng, không đổi phòng được.")
      return render_invalid(booking)
    end
    ok = Booking.transaction do
      (changes.key?(:pays_own) ? booking.update(pays_own: changes[:pays_own]) : true) &&
        (room.nil? || room == booking.room || (booking.checked_in_at ? booking.move_to(room) : booking.update(room:))) ||
        raise(ActiveRecord::Rollback)
    end
    ok ? render_group : render_invalid(booking)
  end

  private
    def render_group(status: :ok) = render(json: MiniApp::GroupSerializer.new(@group.reload, params: serializer_params), status:)
end
