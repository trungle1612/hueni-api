class User < ApplicationRecord
  ROLE_LABELS = { "admin" => "Quản trị viên", "user" => "Thành viên" }.freeze

  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :api_tokens, dependent: :delete_all
  has_many :notification_reads, dependent: :delete_all
  has_many :place_memberships, dependent: :destroy
  has_many :places, through: :place_memberships

  # Stored as 10 digits starting with 0: spaces/dots/dashes dropped, +84 / 84 prefix turned into 0.
  normalizes :phone_number, with: ->(phone) { phone.gsub(/\D/, "").sub(/\A84(?=\d{9}\z)/, "0") }

  enum :role, { admin: "admin", user: "user" }, validate: true

  validates :name, presence: true
  validates :phone_number, presence: true, if: :phone_required?
  validates :phone_number, uniqueness: { allow_nil: true }, format: { with: /\A0\d{9}\z/, allow_blank: true }
  validates :password, length: { minimum: 8 }, allow_nil: true
  validates :zalo_id, uniqueness: true, allow_nil: true
  validates :terms_version, length: { maximum: 20 }

  # One-time link (sent over Zalo): admins choose a password, everyone else links their Zalo (#97).
  # Any password change, including the new placeholder when Zalo gets linked, invalidates every earlier link.
  generates_token_for :password_setup, expires_in: 7.days do
    password_salt.last(10)
  end

  # Joined with a mã mời (#211): Zalo only, no phone. Everyone else (and anyone who once had one) keeps a phone.
  def phone_required? = !deleted? && (new_record? ? zalo_id.nil? : !phone_number_in_database.nil?)

  # Placeholder password nobody knows: the account stays locked until it's set through the link.
  def self.unknown_password = SecureRandom.base58(24)

  def role_label = ROLE_LABELS.fetch(role)

  # Lost phone, new Zalo account or forgotten password: locks the old password, unlinks Zalo,
  # kills older links and logs out everywhere. Then send a new link.
  def reset_login!
    update!(password: User.unknown_password, zalo_id: nil)
    sessions.destroy_all
    api_tokens.delete_all
  end

  # #98: the phone number on a Zalo account (verified by Zalo) links an owner or staff member who has no Zalo yet.
  # `normalizes` turns Zalo's 84… / +84… into our 0…. Never admins. The web login and the Mini App (#152) both use it.
  def self.link_zalo_by_phone(phone, zalo_id, **attributes)
    return if phone.blank? || zalo_id.blank?
    user = User.user.find_by(phone_number: phone, zalo_id: nil)
    user if user&.update(zalo_id:, **attributes)
  end

  def initial = name.to_s.first.to_s.upcase

  DELETED_NAME = "Người dùng đã xoá"
  scope :not_deleted, -> { where(deleted_at: nil) }
  def deleted? = deleted_at.present?

  # Xoá tài khoản (#192, Zalo DPA): personal fields, the Zalo link, logins and memberships go; the row stays,
  # anonymised, so payments, shifts and Hoạt động still resolve. At a homestay where they are the last owner
  # the guest data goes too and the staff leave with them (Place#clear_for_deleted_owner!); the homestay and its rooms stay.
  def delete_account!
    transaction do
      places.merge(PlaceMembership.owner).each do |place|
        place.clear_for_deleted_owner! unless place.place_memberships.owner.where.not(user_id: id).exists?
      end
      place_memberships.reload.each(&:destroy!)
      RegistrationRequest.where(user_id: id).delete_all
      RegistrationRequest.where(zalo_id:).delete_all if zalo_id
      sessions.destroy_all
      api_tokens.delete_all
      notification_reads.delete_all
      update!(name: DELETED_NAME, phone_number: nil, zalo_id: nil, password: User.unknown_password,
        terms_version: nil, terms_accepted_at: nil, deleted_at: Time.current)
    end
  end

  # The single access rule for admin code: look records up only through these.
  # Out-of-scope `find` raises RecordNotFound, which Rails renders as 404.
  # Homestay data belongs to its members, admins included: an admin runs accounts, not homestays (#85).
  def accessible_places = Place.where(id: place_memberships.unlocked.select(:place_id))
  def accessible_rooms = Room.where(place_id: accessible_places.select(:id))
  def accessible_calendar_feeds = CalendarFeed.where(room_id: accessible_rooms.select(:id))
  def accessible_bookings = Booking.where(room_id: accessible_rooms.select(:id))

  # The membership that counts at this homestay: none when locked (#168).
  def membership_at(place) = place_memberships.unlocked.find_by(place:)

  # "owner" | "staff" | nil at this homestay.
  def role_at(place) = membership_at(place)&.role

  # The one authorization rule, shaped like Pundit / Action Policy so a later switch is mechanical.
  # Scoping (accessible_*) still decides what you can see at all.
  def allowed_to?(action, place)
    membership = membership_at(place)
    case action
    when :manage then membership&.owner? || false
    # Front-desk work (check-in/out, no-show, room move, lưu trú, cleaning): owners and staff.
    when :operate then membership.present?
    # Quyền thêm (#168, ADR-001): owners, or staff given that right at this homestay.
    when :discount, :refund, :report then membership&.allows?(action) || false
    else raise ArgumentError, "unknown action #{action.inspect}"
    end
  end
end
