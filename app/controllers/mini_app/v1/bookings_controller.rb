# Bookings in the Mini App (#153, #154): the same model calls and rules as Admin::BookingsController.
# Every change answers with the booking detail; a refusal is 422 with errors per field.
class MiniApp::V1::BookingsController < MiniApp::V1::BaseController
  before_action :set_place, only: :create
  before_action :set_booking, only: %i[update discount]
  before_action :set_any_booking, only: %i[show history check_in check_out no_show undo_check_in undo_check_out move declare]
  before_action -> { authorize!(:operate, @place) }, only: %i[discount check_in check_out no_show move declare]
  before_action -> { authorize!(:manage, @place) }, only: %i[history undo_check_in undo_check_out]

  def show = render_booking(@booking)

  # Lịch sử (#158), owners only: this booking's changes, its payments and services included (Booking#history).
  def history = render(json: activity_page(@booking.history))

  def create
    @booking = @place.rooms.find(params.expect(booking: [ :room_id ])[:room_id]).bookings.build(booking_params)
    @booking.save ? render_booking(@booking, status: :created) : render_invalid(@booking)
  end

  # Edit, or cancel with status "cancelled" + cancel_reason; refund_method refunds what was paid (owners only).
  def update
    if @booking.checked_out_at
      @booking.errors.add(:base, "Khách đã trả phòng, không sửa được đặt phòng.")
      render_invalid(@booking)
    else
      respond @booking.update_and_refund(booking_params, (params[:refund_method].presence_in(Payment::METHODS.keys) if manage?))
    end
  end

  # Giảm giá: "50k" or "10%"; staff at most Booking::STAFF_DISCOUNT_PERCENT. Blank removes it.
  def discount
    cap = Booking::STAFF_DISCOUNT_PERCENT unless manage?
    respond @booking.apply_discount(params.dig(:booking, :discount), params.dig(:booking, :discount_reason), cap:)
  end

  # collect: true = Thu X và nhận phòng (what is due, in cash); else it stays owed. guests: required when the booking has none.
  def check_in
    guests = params[:guests].presence&.to_i
    if guests.nil? && @booking.guests.nil?
      @booking.errors.add(:guests, "cần nhập khi nhận phòng")
      render_invalid(@booking)
    else
      respond @booking.collecting_due(collect?) { @booking.check_in(guests:) }
    end
  end

  def check_out = respond(@booking.collecting_due(collect?) { @booking.check_out })
  def no_show = respond(@booking.no_show)
  def undo_check_in = respond(@booking.undo_check_in)
  def undo_check_out = respond(@booking.undo_check_out)
  def move = respond(@booking.move_to(@place.rooms.find(params.expect(:room_id))))
  def declare = respond(@booking.declare)

  private
    def set_place
      @place = Current.user.accessible_places.find(params[:place_id])
    end

    # iCal bookings are read-only: they come from the OTA and are replaced on every sync.
    def set_booking
      @booking = Current.user.accessible_bookings.manual.find(params[:id])
      @place = @booking.room.place
    end

    # OTA guests arrive too, so unlike update this includes iCal bookings.
    def set_any_booking
      @booking = Current.user.accessible_bookings.find(params[:id])
      @place = @booking.room.place
    end

    def respond(ok) = ok ? render_booking(@booking) : render_invalid(@booking)

    def collect? = ActiveModel::Type::Boolean.new.cast(params[:collect])

    def booking_params
      quote = %i[price weekend_price] if manage? # staff never see prices
      params.expect(booking: [ :start_date, :end_date, :status, :guests, :guest_name, :guest_phone, :note, :deposit, :deposit_method, :cancel_reason, :cancel_reason_other, *quote ])
    end
end
