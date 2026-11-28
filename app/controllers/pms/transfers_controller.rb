# Đưa đón sân bay (#307): Đã đón / Đã đưa from the booking or Yêu cầu đặt phòng, for anyone at the desk.
class Pms::TransfersController < Pms::BaseController
  def done
    transfer = Transfer.where(place: Current.user.accessible_places).find(params[:id])
    authorize!(:operate, transfer.place)
    if transfer.finish
      flash[:toast] = transfer.arrival? ? "Đã đón khách ở sân bay" : "Đã đưa khách ra sân bay"
    else
      flash[:alert] = transfer.errors.full_messages.to_sentence
    end
    redirect_back_or_to (transfer.booking ? pms_booking_path(transfer.booking) : pms_booking_requests_path), status: :see_other
  end
end
