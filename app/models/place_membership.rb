class PlaceMembership < ApplicationRecord
  ROLE_LABELS = { "owner" => "Chủ", "staff" => "Nhân viên" }.freeze
  LAST_OWNER = "Homestay cần ít nhất một chủ.".freeze

  belongs_to :user
  belongs_to :place
  has_paper_trail only: %i[user_id role permissions locked_at], meta: { place_id: :place_id }

  enum :role, { owner: "owner", staff: "staff" }, validate: true

  # Quyền thêm for staff (#168, ADR-001); owners have them all. discount is on by default (STAFF_DISCOUNT_PERCENT).
  PERMISSIONS = { "discount" => "Giảm giá đến #{Booking::STAFF_DISCOUNT_PERCENT}%", "refund" => "Hoàn tiền không cần duyệt", "report" => "Xem báo cáo" }.freeze
  def permissions=(value)
    super(Array(value).map(&:to_s).compact_blank.uniq)
  end
  validate -> { errors.add(:permissions, "không hợp lệ") unless (permissions - PERMISSIONS.keys).empty? }

  # A locked member has lost this homestay: scoping and allowed_to? skip the membership.
  scope :unlocked, -> { where(locked_at: nil) }
  validate -> { errors.add(:base, "Không khoá được chủ homestay.") }, if: -> { owner? && locked_at }

  def locked? = locked_at.present?
  def allows?(permission) = owner? || permissions.include?(permission.to_s)

  # Khoá tài khoản: out of this homestay, and logged out of the app and the web everywhere.
  def lock!
    transaction do
      update!(locked_at: Time.current)
      user.api_tokens.delete_all
      user.sessions.destroy_all
    end
  end

  validates :place_id, uniqueness: { scope: :user_id }
  validate :place_keeps_an_owner, on: :update, if: -> { role_changed?(from: "owner") }
  before_destroy :ensure_place_keeps_an_owner

  def role_label = ROLE_LABELS.fetch(role)

  private
    def other_owners? = place.place_memberships.owner.where.not(id:).exists?

    def place_keeps_an_owner
      errors.add(:base, LAST_OWNER) unless other_owners?
    end

    # Deleting the user or the homestay itself (dependent: :destroy) is fine.
    def ensure_place_keeps_an_owner
      return if !owner? || destroyed_by_association || other_owners?
      errors.add(:base, LAST_OWNER)
      throw :abort
    end
end
