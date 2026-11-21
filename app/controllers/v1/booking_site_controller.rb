# Trang đặt phòng riêng (#172), the API behind hueni.me's booking page: the homestay's offer, a guest's request, and
# the guest's status link. Never another guest's data; the request answers with the booking code, amounts and bank only.
# Approve mode (#282): the request is a BookingRequest (pending until the homestay answers); its link follows it to the booking.
class V1::BookingSiteController < V1::BaseController
  rate_limit to: 60, within: 1.minute, only: %i[show status]
  rate_limit to: 5, within: 10.minutes, only: :create,
    with: -> { render json: { error: "rate_limited", message: "Thử lại sau ít phút." }, status: :too_many_requests }

  # ?from=&to= (YYYY-MM-DD): rooms left and the cheapest stay per room type for those nights; rooms (#290): each room of
  # those types, free on hue-ni and its stay for those nights.
  def show
    place = Place.find_by!(slug: params[:slug])
    return render(json: { name: place.name, open: false }) unless place.site_open
    from, to = date_param(:from), date_param(:to)
    from = to = nil unless from && to&.after?(from) && to - from <= Place::SITE_MAX_NIGHTS
    rooms = place.rooms.where(active: true, room_type: place.site_room_types).order(:name).to_a
    by_type = rooms.group_by(&:room_type)
    render json: {
      name: place.name, open: true,
      deposit_percent: place.site_deposit_percent, hold_minutes: place.site_hold_minutes, cutoff_hour: place.site_cutoff_hour,
      mode: place.site_mode, reply_minutes: place.site_reply_minutes,
      check_in: place.check_in_time, check_out: place.check_out_time, rules: place.house_rules,
      room_types: by_type.map do |type, typed|
        free = (place.site_free_rooms(typed, from, to).map { Booking.new(room: it, start_date: from, end_date: to) } if from)
        { key: type, label: Room::ROOM_TYPES[type], max_guests: typed.map(&:max_guests).max,
          left: free&.size, total: free&.filter_map(&:room_total)&.min }
      end,
      rooms: rooms.map do |room|
        { id: room.id, name: room.name, room_type: room.room_type, max_guests: room.max_guests,
          free: (place.site_free_rooms(by_type[room.room_type], from, to, keep: room).include?(room) if from),
          total: (Booking.new(room:, start_date: from, end_date: to).room_total if from) }
      end
    }
  end

  # { booking: { room_type, start_date, end_date, guests, guest_name, guest_phone, note } }, or room_id (#290) in place of
  # room_type. website is a honeypot.
  def create
    place = Place.find_by!(slug: params[:slug])
    attrs = params.expect(booking: %i[room_type room_id start_date end_date guests guest_name guest_phone note website])
    return render(json: { error: "invalid", message: "Không gửi được.", errors: {} }, status: :unprocessable_entity) if attrs[:website].present?
    made = PaperTrail.request(whodunnit: Activity::SITE) { place.book_online(**attrs.except(:website).to_h.symbolize_keys) }
    if made.persisted?
      render json: status_json(made).merge(token: made.signed_id(purpose: :booking_site, expires_in: 90.days)), status: :created
    else
      render json: { error: "invalid", message: made.errors.full_messages.to_sentence, errors: made.errors.to_hash(true) }, status: :unprocessable_entity
    end
  end

  # The guest's link: pending / declined / expired (a request), held (with the bank to pay) / confirmed / cancelled.
  def status
    made = Booking.find_signed(params[:token], purpose: :booking_site) || BookingRequest.find_signed(params[:token], purpose: :booking_site)
    raise ActiveRecord::RecordNotFound unless made
    render json: status_json(made)
  end

  private
    def status_json(made)
      return request_json(made) if made.is_a?(BookingRequest)
      booking, place = made, made.room.place
      {
        code: booking.code, status: booking.cancelled? ? "cancelled" : booking.held? ? "held" : "confirmed",
        hold_expires_at: booking.hold_expires_at, homestay: place.name,
        start_date: booking.start_date, end_date: booking.end_date, room_type: booking.room.room_type_label, room: booking.room.name, guests: booking.guests,
        total: booking.total, deposit: booking.site_deposit, paid: booking.paid,
        bank: ({ name: place.bank_name, account: place.bank_account, holder: place.bank_holder, content: booking.code.delete("-") } if booking.held? && place.bank?),
        phone: (place.phone if place.site_show_phone)
      }
    end

    # Accepted: the booking's status (its deposit at the % picked on accept), with the request's code.
    def request_json(request)
      return status_json(request.booking).merge(request: request.code, deposit: request.booking.site_deposit(request.deposit_percent)) if request.accepted?
      {
        code: request.code, status: request.site_status, reply_by: request.reply_by, homestay: request.place.name,
        start_date: request.start_date, end_date: request.end_date, room_type: Room::ROOM_TYPES[request.room_type], room: request.room&.name, guests: request.guests,
        reason: (BookingRequest::DECLINE_REASONS[request.decline_reason] if request.declined?),
        suggested: ({ start_date: request.suggested_start_date, end_date: request.suggested_end_date } if request.suggested_start_date)
      }
    end

    def date_param(name) = Date.iso8601(params[name].to_s) rescue nil
end
