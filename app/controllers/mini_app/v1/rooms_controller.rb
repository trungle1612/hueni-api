# Dọn xong and Bảo trì (#154), like Admin::RoomsController#clean / #maintenance: staff too. Answers with the room.
class MiniApp::V1::RoomsController < MiniApp::V1::BaseController
  before_action do
    @room = Current.user.accessible_rooms.find(params[:id])
    @place = @room.place
    authorize!(:operate, @place)
  end

  # Dọn xong, or Xong bảo trì for a room in maintenance.
  def clean
    @room.clean!
    render_room
  end

  # Blocks the room from today through maintenance_until; not while a guest is in.
  def maintenance
    @room.update(params.expect(room: %i[maintenance_reason maintenance_until]).merge(housekeeping: "maintenance")) ? render_room : render_invalid(@room)
  end

  private
    def render_room = render(json: MiniApp::RoomSerializer.new(@room, params: serializer_params))
end
