# Nhận phòng / Trả phòng from Hôm nay (#229) and Chi tiết đặt phòng (#231), Hoàn tác for owners; Đổi phòng and Đã khai báo lưu trú
# for anyone at the desk (#247). The toast after Nhận / Trả offers Hoàn tác (flash[:undo]).
class Pms::StaysController < Pms::BaseController
  before_action :set_booking
  before_action -> { authorize!(:operate, @booking.room.place) }, only: %i[check_in check_out move declare]
  before_action -> { authorize!(:manage, @booking.room.place) }, only: %i[undo_check_in undo_check_out]

  def check_in
    done "Đã nhận phòng", :check_in, @booking.collecting_due(params[:collect]) { @booking.check_in(guests: params[:guests].presence&.to_i) }
  end

  def check_out
    done "Đã trả phòng", :check_out, @booking.collecting_due(params[:collect]) { @booking.check_out }
  end

  def undo_check_in = done("Đã hoàn tác nhận phòng", nil, @booking.undo_check_in)
  def undo_check_out = done("Đã hoàn tác trả phòng", nil, @booking.undo_check_out)

  # A free room of the same homestay; the old one turns dirty.
  def move
    from = @booking.room.name
    room = @booking.room.place.rooms.find(params.expect(:room_id))
    done "Đã đổi phòng #{from} →", nil, @booking.move_to(room)
  end

  def declare = done("Đã khai báo lưu trú", nil, @booking.declare)

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
      redirect_back_or_to pms_today_path, status: :see_other
    end
end
