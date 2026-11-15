# Chờ duyệt (#245, #247): staff without the refund right ask for a refund on Chi tiết đặt phòng; an owner approves it on
# Nhân viên (the refund is written) or rejects it.
class Pms::RefundRequestsController < Pms::BaseController
  before_action only: %i[approve reject] do
    @request = RefundRequest.joins(:booking).merge(Current.user.accessible_bookings).find(params[:id])
    authorize!(:manage, @request.booking.room.place)
  end

  def create
    booking = Current.user.accessible_bookings.manual.find(params[:booking_id])
    authorize!(:operate, booking.room.place)
    request = booking.refund_requests.build(params.expect(refund_request: %i[amount payment_method note]).merge(requested_by: Current.user))
    if request.save
      flash[:toast] = "Đã gửi yêu cầu hoàn #{helpers.pms_money(request.amount)}, chờ chủ cơ sở duyệt"
    else
      flash[:alert] = request.errors.full_messages.to_sentence
    end
    redirect_to pms_booking_path(booking), status: :see_other
  end

  def approve
    decided @request.approve(Current.user), "Đã duyệt. Khoản hoàn #{helpers.pms_money(@request.amount)} được ghi vào #{@request.booking.code}"
  end

  def reject
    decided @request.reject(Current.user), "Đã từ chối. Tiền giữ lại, ghi vào nhật ký"
  end

  private
    def decided(ok, toast)
      if ok then flash[:toast] = toast else flash[:alert] = @request.errors.full_messages.to_sentence end
      redirect_to pms_members_path, status: :see_other
    end
end
