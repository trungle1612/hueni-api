# Đặt phòng mới (#232), Chi tiết đặt phòng and Sửa đặt phòng (#231). Same model calls as Admin::BookingsController: anyone at the desk edits,
# cancels and restores; prices and refunds per allowed_to?. iCal bookings open read-only (the OTA owns them).
class Pms::BookingsController < Pms::BaseController
  before_action :set_booking, only: %i[edit update availability]
  before_action :set_place, only: %i[new create rooms guest]

  # From a Lịch phòng cell the room and day are given; else today and the first free room.
  def new
    @booking = draft(params.permit(:start_date, :end_date), params[:room_id])
  end

  # Đặt phòng mới's free rooms and total (turbo-frame #quote), recomputed from the whole form as it changes.
  def rooms
    @booking = draft(booking_params, params.dig(:booking, :room_id))
    @booking.validate
    render partial: "quote", locals: { booking: @booking, streams: true }
  end

  # Khách cũ (turbo-frame #returning): the guest who stayed before with this phone.
  def guest
    render partial: "returning", locals: { guest: Guest.returning(@place, params.dig(:booking, :guest_phone)) }
  end

  # Name and phone required (context :desk); the overlap and deposit rules are the model's: a busy room sent anyway is refused by the validation.
  def create
    @booking = @place.rooms.find(params.dig(:booking, :room_id)).bookings.build(booking_params)
    if @booking.save(context: %i[create desk])
      redirect_to saved_pms_booking_path(@booking), status: :see_other
    else
      @booking = draft(booking_params, @booking.room_id).tap { it.errors.merge!(@booking.errors) }
      render :new, status: :unprocessable_entity
    end
  end

  # Đã lưu: what was booked, then Xem trên lịch / Đặt phòng khác.
  def saved
    @booking = Current.user.accessible_bookings.manual.find(params[:id])
  end

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

    def set_place
      @place = current_place or raise ActiveRecord::RecordNotFound
      authorize!(:operate, @place)
    end

    # The new-booking form: dates (check-out at least the next day), the asked room while it is free for them, else
    # the first free one; @rooms = the open rooms, @free = those free for the dates (the model's date_problems).
    def draft(attributes, room_id)
      booking = Booking.new(attributes)
      booking.start_date ||= Date.current
      booking.end_date = booking.start_date.next_day unless booking.end_date&.after?(booking.start_date)
      @rooms = @place.rooms.where(active: true).order(:name).to_a
      @free = @rooms.select { Booking.new(room: it, start_date: booking.start_date, end_date: booking.end_date).date_problems.empty? }
      booking.room = @free.find { it.id.to_s == room_id.to_s } || @free.first
      booking
    end

    # Cancelling with money paid: kept, or refunded in full (owners, or staff with the refund right).
    def refund_method = (params[:refund_method].presence_in(Payment::METHODS.keys) if allowed_to?(:refund, @place))

    def booking_params
      quote = %i[price weekend_price] if allowed_to?(:manage, @place) # staff never see prices
      # deposit is Đã cọc on a new booking only (the first payment); room_id is never permitted, rooms come from @place.
      params.expect(booking: [ :start_date, :end_date, :status, :guests, :guest_name, :guest_phone, :note, :deposit, :deposit_method,
        :cancel_reason, :cancel_reason_other, *quote ])
    end
end
