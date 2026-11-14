# Hôm nay / Ngày mai (#229) for the current homestay: the lists come from Today, as on /admin Tổng quan.
class Pms::TodayController < Pms::BaseController
  def show
    return unless current_place
    @tomorrow = params[:day] == "mai"
    @today = Today.new(current_place.rooms, tomorrow: @tomorrow)
    @open_rooms = current_place.rooms.where(active: true).count
    # Hoàn tác in the toast after Nhận / Trả phòng: owners only, like the action.
    @undo = Booking.where(room: current_place.rooms).find_by(id: flash[:undo]&.first) if allowed_to?(:manage, current_place)
  end
end
