# Owner self-registration, after a Zalo login that matched no account (ZaloSessionsController#start_registration
# keeps the Zalo id in session[:registration] for 30 minutes). An admin calls to verify, then approves
# (Admin::RegistrationRequestsController). Staff don't register: their owner adds them in Thành viên.
class RegistrationsController < ApplicationController
  HELP_PHONE = "0794521276"

  allow_unauthenticated_access
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to registration_path, alert: "Thử lại sau ít phút." }
  before_action :require_zalo_login, except: :destroy

  # Pending: the status page, or the form to correct it (?sua=1). Rejected: the form, prefilled with what was sent.
  def new
    @latest = latest_request
    @registration =
      if @latest&.pending? then (@latest if params[:sua])
      elsif @latest&.rejected? then RegistrationRequest.new(@latest.slice(:name, :phone_number, :place_name, :maps_url))
      else RegistrationRequest.new(name: @zalo["zalo_name"])
      end
  end

  def create
    @registration = RegistrationRequest.new(registration_params.merge(zalo_id: @zalo["zalo_id"], zalo_name: @zalo["zalo_name"]))
    @registration.place = matching_place(@registration.place_name)
    if @registration.save
      NotifyRegistrationJob.perform_later(@registration, admin_registration_request_url(@registration))
      redirect_to registration_path
    else
      @latest = latest_request
      render :new, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotUnique # already one pending for this Zalo (double submit)
    redirect_to registration_path
  end

  # Corrects the pending request in place: the admin's link keeps working and shows the new details.
  def update
    @latest = @registration = latest_request
    return redirect_to registration_path unless @registration&.pending?

    @registration.assign_attributes(registration_params)
    @registration.place = matching_place(@registration.place_name)
    if @registration.save
      redirect_to registration_path, notice: "Đã cập nhật thông tin."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    session.delete(:registration)
    redirect_to new_session_path
  end

  private
    def require_zalo_login
      @zalo = session[:registration]
      if @zalo.nil? || @zalo["expires_at"].to_i <= Time.current.to_i
        session.delete(:registration)
        redirect_to new_session_path, alert: "Phiên đăng ký hết hạn. Đăng nhập Zalo lại."
      elsif User.exists?(zalo_id: @zalo["zalo_id"]) # approved (or linked) meanwhile
        session.delete(:registration)
        redirect_to new_session_path, notice: "Tài khoản đã được duyệt. Bấm Đăng nhập bằng Zalo."
      end
    end

    def latest_request = RegistrationRequest.where(zalo_id: @zalo["zalo_id"]).order(:id).last

    def registration_params = params.expect(registration_request: %i[name phone_number place_name maps_url])

    # The name picked from the suggestions (or typed exactly). Two homestays with that name → none: the admin picks.
    def matching_place(name)
      places = Place.where(name: name.to_s.strip).limit(2).to_a
      places.first if places.one?
    end
end
