# Nhận phòng / Trả phòng from Hôm nay (#229), Hoàn tác for owners. Same model calls as Admin::BookingsController;
# the toast after it offers Hoàn tác (flash[:undo]).
class Pms::StaysController < Pms::BaseController
  before_action :set_booking
  before_action -> { authorize!(:operate, @booking.room.place) }, only: %i[check_in check_out]
  before_action -> { authorize!(:manage, @booking.room.place) }, only: %i[undo_check_in undo_check_out]

  def check_in
    done "Đã nhận phòng", :check_in, @booking.collecting_due(params[:collect]) { @booking.check_in(guests: params[:guests].presence&.to_i) }
  end

  def check_out
    done "Đã trả phòng", :check_out, @booking.collecting_due(params[:collect]) { @booking.check_out }
  end

  def undo_check_in = done("Đã hoàn tác nhận phòng", nil, @booking.undo_check_in)
  def undo_check_out = done("Đã hoàn tác trả phòng", nil, @booking.undo_check_out)

  private
    def set_booking
      @booking = Current.user.accessible_bookings.find(params[:id])
    end

    def done(text, step, ok)
      if ok
        money = if @booking.collected then " · đã thu #{helpers.pms_money(@booking.collected)}"
        elsif @booking.owed then " · ghi nợ #{helpers.pms_money(@booking.owed)}"
        end
        flash[:toast] = "#{text} #{@booking.room.name}#{money}"
        flash[:undo] = [ @booking.id, step.to_s ] if step
      else
        flash[:alert] = @booking.errors.full_messages.to_sentence
      end
      redirect_to pms_today_path, status: :see_other
    end
end
