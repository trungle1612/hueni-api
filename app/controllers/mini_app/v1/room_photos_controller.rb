# Ảnh phòng (#187), owners only like the rest of the room setup. Both answer with the room (photos: [{ id, url }]).
class MiniApp::V1::RoomPhotosController < MiniApp::V1::BaseController
  before_action :set_room

  # multipart photo: one file; the 11th, a wrong type or a too large file → 422 on errors.photos.
  def create
    return render_invalid(@room) unless @room.update(photo_files: [ params.require(:photo) ])
    render json: MiniApp::RoomSerializer.new(@room.reload, params: serializer_params), status: :created
  end

  def destroy
    @room.photos.find(params[:id]).destroy!
    render json: MiniApp::RoomSerializer.new(@room.reload, params: serializer_params)
  end

  private
    def set_room
      @room = Current.user.accessible_rooms.find(params[:room_id])
      @place = @room.place
      authorize!(:manage, @place)
    end
end
