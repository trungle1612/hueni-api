class Admin::BookingsController < Admin::BaseController
  before_action :set_place, only: %i[new create availability]
  before_action :set_booking, only: %i[edit update discount]
  before_action -> { authorize!(:discount, @place) }, only: :discount
  before_action :set_any_booking, only: %i[check_in check_out no_show undo_check_in undo_check_out move declare]
  before_action -> { authorize!(:operate, @booking.room.place) }, only: %i[check_in check_out no_show move declare]
  before_action -> { authorize!(:manage, @booking.room.place) }, only: %i[undo_check_in undo_check_out]

  # From a calendar cell the room and day are given; "+ Đặt phòng" picks the first room free that night.
  def new
    start_date = date_param(:start_date) || Date.current
    rooms = @place.rooms.where(active: true).order(:name)
    room = params[:room_id] ? @place.rooms.find(params[:room_id]) :
      rooms.find { Booking.new(room: it, start_date:, end_date: start_date.next_day).date_problems.empty? } || rooms.first
    @booking = Booking.new(room:, start_date:, end_date: start_date.next_day)
  end

  # The form's live "còn trống / trùng lịch" line (turbo-frame #availability).
  def availability
    room = @place.rooms.find(params[:room_id])
    booking = Booking.new(room:, start_date: date_param(:start_date), end_date: date_param(:end_date), id: params[:booking_id].presence)
    render partial: "availability", locals: { booking:, place: @place }
  end

  def create
    @booking = @place.rooms.find(params.dig(:booking, :room_id)).bookings.build(booking_params)
    if @booking.save
      redirect_to back_to_calendar, notice: "Đã lưu đặt phòng."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @booking.checked_out_at
      redirect_to edit_admin_booking_path(@booking), alert: "Khách đã trả phòng, không sửa được đặt phòng."
    elsif @booking.update_and_refund(booking_params, refund_method)
      refund = @booking.refund
      redirect_to back_to_calendar, notice: @booking.cancelled? ? "Đã huỷ đặt phòng.#{" Đã hoàn #{helpers.vnd(refund.amount)}." if refund}" : "Đã lưu đặt phòng."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Giảm giá (#140).
  def discount
    cap = Booking::STAFF_DISCOUNT_PERCENT unless allowed_to?(:manage, @place)
    if @booking.apply_discount(params.dig(:booking, :discount), params.dig(:booking, :discount_reason), cap:)
      notice = @booking.discount ? "Đã giảm #{helpers.vnd(@booking.discount)}." : "Đã bỏ giảm giá."
      redirect_to edit_admin_booking_path(@booking, anchor: "thanh-toan"), notice:
    else
      redirect_to edit_admin_booking_path(@booking, anchor: "thanh-toan"), alert: @booking.errors.full_messages.to_sentence
    end
  end

  # The head count is required at the desk when the booking has none.
  def check_in
    guests = params[:guests].presence&.to_i
    if guests.nil? && @booking.guests.nil?
      redirect_back_or_to admin_root_path, alert: "Nhập số khách khi nhận phòng"
    elsif @booking.collecting_due(params[:collect]) { @booking.check_in(guests:) }
      redirect_back_or_to admin_root_path, notice: "Đã nhận phòng: #{stay_label}#{money_note}"
    else
      redirect_back_or_to admin_root_path, alert: @booking.errors.full_messages.to_sentence
    end
  end

  def check_out
    if @booking.collecting_due(params[:collect]) { @booking.check_out }
      redirect_back_or_to admin_root_path, notice: "Đã trả phòng: #{stay_label}#{money_note}. Phòng chuyển sang chưa dọn."
    else
      redirect_back_or_to admin_root_path, alert: @booking.errors.full_messages.to_sentence
    end
  end

  def no_show
    if @booking.no_show
      redirect_back_or_to admin_root_path, notice: "Đã huỷ (không đến): #{stay_label}"
    else
      redirect_back_or_to admin_root_path, alert: @booking.errors.full_messages.to_sentence
    end
  end

  def undo_check_in
    if @booking.undo_check_in
      redirect_back_or_to admin_root_path, notice: "Đã hoàn tác nhận phòng: #{stay_label}"
    else
      redirect_back_or_to admin_root_path, alert: @booking.errors.full_messages.to_sentence
    end
  end

  def undo_check_out
    if @booking.undo_check_out
      redirect_back_or_to admin_root_path, notice: "Đã hoàn tác trả phòng: #{stay_label}"
    else
      redirect_back_or_to admin_root_path, alert: @booking.errors.full_messages.to_sentence
    end
  end

  def move
    room = @booking.room.place.rooms.find(params.expect(:room_id))
    from = @booking.room.name
    if @booking.move_to(room)
      redirect_back_or_to admin_root_path, notice: "Đã đổi phòng: #{helpers.booking_label(@booking)} · #{from} → #{room.name}. Phòng #{from} chuyển sang chưa dọn."
    else
      redirect_back_or_to admin_root_path, alert: @booking.errors.full_messages.to_sentence
    end
  end

  def declare
    if @booking.declare
      redirect_back_or_to admin_root_path, notice: "Đã khai báo lưu trú: #{stay_label}"
    else
      redirect_back_or_to admin_root_path, alert: @booking.errors.full_messages.to_sentence
    end
  end

  private
    def set_place
      @place = Current.user.accessible_places.find_by!(slug: params[:place_slug])
    end

    # iCal bookings are read-only: they come from the OTA and are replaced on every sync.
    def set_booking
      @booking = Current.user.accessible_bookings.manual.find(params[:id])
      @place = @booking.room.place
    end

    # OTA guests arrive too, so unlike edit/update this includes iCal bookings.
    def set_any_booking
      @booking = Current.user.accessible_bookings.find(params[:id])
    end

    # Cancelling with money paid asks what happens to it (#139): kept, or refunded in full (owners only).
    def refund_method = (params[:refund_method].presence_in(Payment::METHODS.keys) if allowed_to?(:refund, @place))

    def money_note
      if @booking.collected then " · đã thu #{helpers.vnd(@booking.collected)}"
      elsif @booking.owed then " · còn nợ #{helpers.vnd(@booking.owed)}"
      end
    end

    def stay_label = "#{helpers.booking_label(@booking)} · #{@booking.room.name}"

    def booking_params
      quote = %i[price weekend_price] if Current.user.allowed_to?(:manage, @place) # staff never see prices
      params.expect(booking: [ :start_date, :end_date, :status, :guests, :guest_name, :guest_phone, :note, :deposit, :deposit_method, :cancel_reason, :cancel_reason_other, *quote ])
    end

    # Back to the timeline, scrolled to the booking when it's outside the default range.
    def back_to_calendar
      shown = Date.current...(Date.current + Admin::CalendarsController::DAYS)
      admin_place_calendar_path(@place.slug, from: (@booking.start_date unless shown.cover?(@booking.start_date)))
    end
end
