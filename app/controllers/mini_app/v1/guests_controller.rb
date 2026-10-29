# Hồ sơ khách (#165): owners and staff. Names and phones never travel in a URL: the list is a POST with q in the body
# (filtered from logs), and a profile is reached through one of the guest's bookings.
class MiniApp::V1::GuestsController < MiniApp::V1::BaseController
  LIMIT = 50

  before_action :set_place, only: :index
  before_action :set_guest, except: :index
  before_action -> { authorize!(:operate, @place) }

  # q: name (with or without diacritics), phone digits or DP code; blank = the guests with the latest stays.
  def index
    query = params[:q].to_s.squish.first(50)
    stays = Guest.stays(@place)
    keys = query.empty? ? stays.keys : Booking.where(room: @place.rooms).search(query).filter_map { Guest.key_for(it) }.uniq
    saved = @place.guests.where(key: keys).index_by(&:key)
    guests = keys.map { |key| (saved[key] || Guest.new(place: @place, key:)).tap { it.bookings = stays.fetch(key) } }
    guests = guests.sort_by { -it.latest.start_date.jd }.first(LIMIT)
    render json: { guests: MiniApp::GuestSerializer.new(guests) }
  end

  def show = render_guest

  # { guest: { note, flag } }: flag = the reason for Cần lưu ý, blank removes it.
  def update
    @guest.save_details(params.expect(guest: %i[note flag])) ? render_guest : render_invalid(@guest)
  end

  private
    def set_place
      @place = Current.user.accessible_places.find(params[:id])
    end

    def set_guest
      booking = Current.user.accessible_bookings.find(params[:booking_id])
      @place = booking.room.place
      @guest = Guest.of(booking) or raise ActiveRecord::RecordNotFound
    end

    def render_guest = render(json: MiniApp::GuestProfileSerializer.new(@guest, params: serializer_params))
end
