# Chờ duyệt (#168): staff without the refund right ask for a refund; owners approve (the refund is written) or reject.
class MiniApp::V1::RefundRequestsController < MiniApp::V1::BaseController
  # { refund_request: { amount, payment_method, note } }, by anyone at the desk.
  def create
    booking = Current.user.accessible_bookings.manual.find(params[:booking_id])
    authorize!(:operate, @place = booking.room.place)
    request = booking.refund_requests.build(params.expect(refund_request: %i[amount payment_method note]).merge(requested_by: Current.user))
    request.save ? render(json: request_json(request), status: :created) : render_invalid(request)
  end

  # Owners: the pending requests of this homestay, oldest first.
  def index
    @place = Current.user.accessible_places.find(params[:place_id])
    authorize!(:manage, @place)
    requests = RefundRequest.pending.joins(booking: :room).where(rooms: { place_id: @place.id }).includes(:requested_by, booking: :room).order(:created_at)
    render json: { refund_requests: requests.map { request_json(it) } }
  end

  def approve = decide { @request.approve(Current.user) }
  def reject = decide { @request.reject(Current.user) }

  private
    def decide
      @request = RefundRequest.joins(:booking).merge(Current.user.accessible_bookings).find(params[:id])
      authorize!(:manage, @place = @request.booking.room.place)
      yield ? render(json: request_json(@request)) : render_invalid(@request)
    end

    def request_json(request)
      booking = request.booking
      request.slice(:id, :amount, :payment_method, :note, :status, :decided_at).merge(
        at: request.created_at, by: request.requested_by&.name, payment_id: request.payment_id,
        booking: { id: booking.id, code: booking.code, label: booking.label, room_name: booking.room.name, paid: booking.paid })
    end
end
