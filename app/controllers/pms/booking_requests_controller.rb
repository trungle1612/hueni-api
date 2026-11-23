# Yêu cầu đặt phòng (#284, board Requests.dc.html, owner and staff): the current homestay's requests from hue-ni of the
# last BookingRequest::DAYS days in tabs Chờ trả lời / Đã nhận / Từ chối, hết hạn, answered with Nhận
# (BookingRequest#accept) or Từ chối (#decline); the homestay then calls or Zalos the guest itself (#292). The toast
# offers Hoàn tác (#undo) for a while. The model decides availability; refusals come back as its messages.
class Pms::BookingRequestsController < Pms::BaseController
  TABS = %w[da-nhan tu-choi].freeze

  before_action(only: :index) { authorize!(:operate, current_place) if current_place }
  before_action only: %i[accept decline undo] do
    @request = BookingRequest.where(place: Current.user.accessible_places).find(params[:id])
    authorize!(:operate, @request.place)
  end

  def index
    @tab = params[:loc].presence_in(TABS)
    @requests = current_place&.booking_requests&.where(created_at: BookingRequest::DAYS.days.ago..)&.includes(:room, booking: :room)&.to_a
    @undo = @requests&.find { it.id == flash[:undo].first } if flash[:undo]&.last == "request"
  end

  def accept
    room = @request.place.rooms.find_by(id: params[:room_id])
    if room && @request.accept(room:, deposit_percent: params[:deposit_percent])
      redirect_to pms_booking_requests_path(loc: "da-nhan"), status: :see_other,
        flash: { toast: "Đã nhận, đã tạo đặt phòng. Gọi hoặc nhắn #{@request.guest_name} ngay", undo: [ @request.id, "request" ] }
    else
      redirect_to pms_booking_requests_path, status: :see_other, alert: room ? @request.errors.full_messages.to_sentence : "Chọn phòng để nhận"
    end
  end

  # Suggested dates go with Hết phòng only.
  def decline
    full = params[:reason] == "full"
    if @request.decline(reason: params[:reason], suggested_start_date: (params[:suggested_start_date] if full),
        suggested_end_date: (params[:suggested_end_date] if full))
      redirect_to pms_booking_requests_path(loc: "tu-choi"), status: :see_other, flash: { toast: "Đã từ chối và báo khách", undo: [ @request.id, "request" ] }
    else
      redirect_to pms_booking_requests_path, status: :see_other, alert: @request.errors.full_messages.to_sentence
    end
  end

  def undo
    if @request.undo
      redirect_to pms_booking_requests_path, status: :see_other, flash: { toast: "Đã hoàn tác, yêu cầu chờ trả lời lại" }
    else
      redirect_to pms_booking_requests_path(loc: @request.accepted? ? "da-nhan" : ("tu-choi" unless @request.pending?)), status: :see_other,
        alert: @request.errors.full_messages.to_sentence
    end
  end
end
