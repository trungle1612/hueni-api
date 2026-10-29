# Đặt phòng theo đoàn (#164): owners and staff; only owners set the group discount (giá đoàn).
# Each room is a normal booking: Bỏ khỏi đoàn = cancel it (PATCH /bookings/:id), Hoàn tác = the booking's own undo.
class MiniApp::V1::GroupsController < MiniApp::V1::BaseController
  before_action :set_place, only: :create
  before_action :set_group, except: :create
  before_action -> { authorize!(:operate, @place) }

  # { group: {...}, room_ids: [..] (≥ 2), start_date:, end_date: }: all rooms are booked or none.
  def create
    @group = @place.groups.build(group_params)
    rooms = @place.rooms.find(Array(params.expect(room_ids: [])))
    if @group.book(rooms, start_date: date_param(:start_date), end_date: date_param(:end_date))
      render_group(status: :created)
    else
      render_invalid(@group)
    end
  end

  def show = render_group

  # Name, contact, origin and the bill (one | split). The discount is fixed when the rooms are booked.
  def update = respond(@group.update(group_params.except(:discount_pct)))

  # Nhận phòng cả đoàn: every room still to arrive, all or nothing.
  def check_in = respond(@group.check_in_all)

  # Thu tiền cho đoàn (one bill): split over the billed rooms' due, in room order.
  def payments
    payment = params.expect(payment: %i[amount payment_method note])
    respond @group.pay(payment[:amount], payment_method: payment[:payment_method], note: payment[:note], user: Current.user)
  end

  private
    def set_place
      @place = Current.user.accessible_places.find(params[:place_id])
    end

    def set_group
      @group = Group.where(place: Current.user.accessible_places).find(params[:id])
      @place = @group.place
    end

    def group_params
      params.expect(group: [ :name, :contact, :phone, :origin, :bill, *(:discount_pct if manage?) ])
    end

    def respond(ok) = ok ? render_group : render_invalid(@group)

    def render_group(status: :ok) = render(json: MiniApp::GroupSerializer.new(@group.reload, params: serializer_params), status:)
end
