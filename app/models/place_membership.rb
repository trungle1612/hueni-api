class PlaceMembership < ApplicationRecord
  ROLE_LABELS = { "owner" => "Chủ", "staff" => "Nhân viên" }.freeze
  LAST_OWNER = "Homestay cần ít nhất một chủ.".freeze

  belongs_to :user
  belongs_to :place

  enum :role, { owner: "owner", staff: "staff" }, validate: true

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
