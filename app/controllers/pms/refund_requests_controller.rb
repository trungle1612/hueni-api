# Chờ duyệt on Nhân viên (#245): an owner approves a staff refund request (the refund is written) or rejects it.
class Pms::RefundRequestsController < Pms::BaseController
  before_action do
    @request = RefundRequest.joins(:booking).merge(Current.user.accessible_bookings).find(params[:id])
    authorize!(:manage, @request.booking.room.place)
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
