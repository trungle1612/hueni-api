# Trang đặt phòng riêng (#172), the API behind hueni.me's booking page: the homestay's offer, a guest's request, and
# the guest's status link. Never another guest's data; the request answers with the booking code, amounts and bank only.
class V1::BookingSiteController < V1::BaseController
  rate_limit to: 60, within: 1.minute, only: %i[show status]
  rate_limit to: 5, within: 10.minutes, only: :create,
    with: -> { render json: { error: "rate_limited", message: "Thử lại sau ít phút." }, status: :too_many_requests }

  # ?from=&to= (YYYY-MM-DD): rooms left and the cheapest stay per room type for those nights.
  def show
    place = Place.find_by!(slug: params[:slug])
    return render(json: { name: place.name, open: false }) unless place.site_open
    from, to = date_param(:from), date_param(:to)
    from = to = nil unless from && to&.after?(from) && to - from <= Place::SITE_MAX_NIGHTS
    rooms = place.rooms.where(active: true, room_type: place.site_room_types).order(:name).to_a
    render json: {
      name: place.name, open: true,
      deposit_percent: place.site_deposit_percent, hold_minutes: place.site_hold_minutes, cutoff_hour: place.site_cutoff_hour,
      room_types: rooms.group_by(&:room_type).map do |type, typed|
        free = (typed.map { Booking.new(room: it, start_date: from, end_date: to) }.select { it.date_problems.empty? } if from)
        { key: type, label: Room::ROOM_TYPES[type], max_guests: typed.map(&:max_guests).max,
          left: free&.size, total: free&.filter_map(&:room_total)&.min }
      end
    }
  end

  # { booking: { room_type, start_date, end_date, guests, guest_name, guest_phone, note } }. website is a honeypot.
  def create
    place = Place.find_by!(slug: params[:slug])
    attrs = params.expect(booking: %i[room_type start_date end_date guests guest_name guest_phone note website])
    return render(json: { error: "invalid", message: "Không gửi được.", errors: {} }, status: :unprocessable_entity) if attrs[:website].present?
    booking = PaperTrail.request(whodunnit: Activity::SITE) { place.book_online(**attrs.except(:website).to_h.symbolize_keys) }
    if booking.persisted?
      render json: status_json(booking).merge(token: booking.signed_id(purpose: :booking_site, expires_in: 90.days)), status: :created
    else
      render json: { error: "invalid", message: booking.errors.full_messages.to_sentence, errors: booking.errors.to_hash(true) }, status: :unprocessable_entity
    end
  end

  # The guest's link: held (with the bank to pay) / confirmed / cancelled.
  def status
    booking = Booking.find_signed(params[:token], purpose: :booking_site) or raise ActiveRecord::RecordNotFound
    render json: status_json(booking)
  end

  private
    def status_json(booking)
      place = booking.room.place
      {
        code: booking.code, status: booking.cancelled? ? "cancelled" : booking.held? ? "held" : "confirmed",
        hold_expires_at: booking.hold_expires_at, homestay: place.name,
        start_date: booking.start_date, end_date: booking.end_date, room_type: booking.room.room_type_label, guests: booking.guests,
        total: booking.total, deposit: booking.site_deposit, paid: booking.paid,
        bank: ({ name: place.bank_name, account: place.bank_account, holder: place.bank_holder, content: booking.code.delete("-") } if booking.held? && place.bank?)
      }
    end

    def date_param(name) = Date.iso8601(params[name].to_s) rescue nil
end
