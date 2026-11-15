# Chi tiết đặt phòng and Sửa đặt phòng (#231). Same model calls as Admin::BookingsController: anyone at the desk edits,
# cancels and restores; prices and refunds per allowed_to?. iCal bookings open read-only (the OTA owns them).
class Pms::BookingsController < Pms::BaseController
  before_action :set_booking, only: %i[edit update availability]

  def show
    @booking = Current.user.accessible_bookings.includes(:payments, :charges, room: :place).find(params[:id])
    @place = @booking.room.place
    @undo = @booking if allowed_to?(:manage, @place) && flash[:undo]&.first == @booking.id
  end

  def edit
  end

  # The form's live date check (turbo-frame #availability), the same validations as saving.
  def availability
    booking = Booking.new(room: @booking.room, start_date: date_param(:start_date), end_date: date_param(:end_date), id: @booking.id)
    render partial: "availability", locals: { booking: }
  end

  # Edit, cancel (status cancelled + cancel_reason, refund_method refunds what was paid) or Khôi phục (status confirmed).
  def update
    was = @booking.status
    if @booking.update_and_refund(booking_params, refund_method)
      flash[:toast] = if @booking.cancelled? && was != "cancelled"
        "Đã huỷ #{@booking.code || "đặt phòng"}#{" · đã hoàn #{helpers.pms_money(@booking.refund.amount)}" if @booking.refund}"
      elsif was == "cancelled" && @booking.confirmed? then "Đã khôi phục đặt phòng"
      else "Đã lưu thay đổi"
      end
      redirect_to pms_booking_path(@booking), status: :see_other
    elsif params.dig(:booking, :status).present?
      redirect_to pms_booking_path(@booking), alert: @booking.errors.full_messages.to_sentence, status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private
    # iCal bookings are read-only: they come from the OTA and are replaced on every sync.
    def set_booking
      @booking = Current.user.accessible_bookings.manual.find(params[:id])
      @place = @booking.room.place
    end

    # Cancelling with money paid: kept, or refunded in full (owners, or staff with the refund right).
    def refund_method = (params[:refund_method].presence_in(Payment::METHODS.keys) if allowed_to?(:refund, @place))

    def booking_params
      quote = %i[price weekend_price] if allowed_to?(:manage, @place) # staff never see prices
      params.expect(booking: [ :start_date, :end_date, :status, :guests, :guest_name, :guest_phone, :note, :cancel_reason, :cancel_reason_other, *quote ])
    end
end
