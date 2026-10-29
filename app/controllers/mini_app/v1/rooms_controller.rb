# Rooms in the Mini App, like Admin::RoomsController: setup (create / update / destroy, #162) is owners only;
# Dọn xong and Bảo trì (#154) are staff too. Answers with the room.
class MiniApp::V1::RoomsController < MiniApp::V1::BaseController
  before_action :set_room, except: :create
  before_action -> { authorize!(:manage, @place) }, only: %i[update destroy]
  before_action -> { authorize!(:operate, @place) }, only: %i[clean maintenance]

  def create
    @place = Current.user.accessible_places.find(params[:place_id])
    authorize!(:manage, @place)
    @room = @place.rooms.build(room_params)
    @room.save ? render_room(status: :created) : render_invalid(@room)
  end

  # notices: what the owner should know (upcoming bookings keep their price, stays above a lowered head count).
  def update
    return render_invalid(@room) unless @room.update(room_params)
    render json: MiniApp::RoomSerializer.new(@room, params: serializer_params).serializable_hash.merge(notices: @room.change_notes)
  end

  # Only a room that never had a booking (Room before_destroy); its feeds go with it.
  def destroy
    @room.destroy ? head(:no_content) : render_invalid(@room)
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
    def set_room
      @room = Current.user.accessible_rooms.find(params[:id])
      @place = @room.place
    end

    def render_room(status: :ok) = render(json: MiniApp::RoomSerializer.new(@room, params: serializer_params), status:)

    def room_params
      params.expect(room: [ :name, :max_guests, :price, :weekend_price, :active, :state, :maintenance_reason, :maintenance_until,
        :floor, :room_type, :note, amenities: [] ])
    end
end
