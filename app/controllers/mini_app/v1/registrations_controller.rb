# Owner registration from the Mini App (#152), like /dang-ky (RegistrationsController): after a not_registered sign-in,
# with its registration_token in the X-Registration-Token header. One pending request per Zalo; the owner can correct it;
# a rejected one can be sent again. An admin approves in Người dùng; then signing in works.
class MiniApp::V1::RegistrationsController < MiniApp::V1::BaseController
  TOKEN_PURPOSE = :mini_app_registration

  skip_before_action :authenticate
  before_action :require_registration_token
  rate_limit to: 10, within: 3.minutes, only: %i[create update],
    with: -> { render json: { error: "rate_limited", message: "Thử lại sau ít phút." }, status: :too_many_requests }

  def self.token_for(zalo) = Rails.application.message_verifier(TOKEN_PURPOSE).generate(zalo.slice(:id, :name), expires_in: 30.minutes)

  def self.request_json(request)
    request&.slice(:id, :status, :name, :phone_number, :place_name, :maps_url, :created_at)&.merge(homestay: request.homestay_name)
  end

  def show = render(json: { registration: self.class.request_json(latest_request) })

  def create
    latest = latest_request
    return render json: { error: "pending", message: "Yêu cầu đăng ký đang chờ duyệt." }, status: :conflict if latest&.pending?

    registration = RegistrationRequest.new(registration_params.merge(zalo_id: @zalo[:id], zalo_name: @zalo[:name]))
    save(registration, :created) { NotifyRegistrationJob.perform_later(registration, admin_registration_request_url(registration)) }
  rescue ActiveRecord::RecordNotUnique # already one pending for this Zalo (double submit)
    show
  end

  # Corrects the pending request in place: the admin's link keeps working and shows the new details.
  def update
    registration = latest_request
    return render json: { error: "not_pending", message: "Không có yêu cầu nào đang chờ duyệt." }, status: :conflict unless registration&.pending?

    registration.assign_attributes(registration_params)
    save(registration, :ok)
  end

  private
    def require_registration_token
      zalo = Rails.application.message_verifier(TOKEN_PURPOSE).verified(request.headers["X-Registration-Token"].to_s)
      @zalo = zalo&.symbolize_keys
      if @zalo.nil?
        render json: { error: "registration_expired", message: "Phiên đăng ký hết hạn. Đăng nhập Zalo lại." }, status: :unauthorized
      elsif User.exists?(zalo_id: @zalo[:id]) # approved (or linked) meanwhile
        render json: { error: "registered", message: "Tài khoản đã được duyệt. Đăng nhập bằng Zalo." }, status: :conflict
      end
    end

    def latest_request = RegistrationRequest.where(zalo_id: @zalo[:id]).order(:id).last

    def registration_params = params.expect(registration: %i[name phone_number place_name maps_url])

    def save(registration, status)
      registration.place = RegistrationRequest.matching_place(registration.place_name)
      if registration.save
        yield if block_given?
        render json: { registration: self.class.request_json(registration) }, status:
      else
        render json: { error: "invalid", message: registration.errors.full_messages.to_sentence, errors: registration.errors.to_hash(true) },
          status: :unprocessable_entity
      end
    end
end
