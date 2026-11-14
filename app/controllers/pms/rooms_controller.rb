# Đã dọn from Hôm nay (#229): staff too, as in /admin.
class Pms::RoomsController < Pms::BaseController
  def clean
    room = Current.user.accessible_rooms.find(params[:id])
    authorize!(:operate, room.place)
    room.clean!
    redirect_to pms_today_path, status: :see_other, flash: { toast: "Đã dọn xong #{room.name}" }
  end
end
