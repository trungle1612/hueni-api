# Ảnh phòng (#187): owners add them with the room form (Room#photo_files=) and delete them here.
class Pms::RoomPhotosController < Pms::BaseController
  def destroy
    room = Current.user.accessible_rooms.find(params[:room_id])
    authorize!(:manage, room.place)
    room.photos.find(params[:id]).destroy!
    redirect_to edit_pms_room_path(room), status: :see_other, flash: { toast: "Đã xoá ảnh" }
  end
end
