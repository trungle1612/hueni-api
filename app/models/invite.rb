# Mã mời (#211): an unknown Zalo account that enters a valid code in the Mini App gets an account and a membership
# at the code's homestay with its role (MiniApp::V1::SessionsController). Each sign-up uses it once, up to max_uses,
# until expires_at. Only admins make and revoke codes (Admin::InvitesController, menu Mã mời, or invites:create).
class Invite < ApplicationRecord
  # Easy to read out and type: no 0/O, 1/I/L.
  ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789".chars.freeze
  LENGTH = 8
  INVALID = "Mã mời không đúng hoặc đã hết hạn.".freeze

  belongs_to :place
  belongs_to :created_by, class_name: "User"

  enum :role, { owner: "owner", staff: "staff" }, validate: true
  # Typed as 7k2p-9qxm or "7K2P 9QXM": the same code.
  normalizes :code, with: ->(code) { code.upcase.gsub(/[^A-Z0-9]/, "") }

  validates :max_uses, numericality: { only_integer: true, in: 1..20, message: "phải từ 1 đến 20" }
  validates :expires_at, presence: true

  before_validation on: :create do
    self.code ||= Array.new(LENGTH) { ALPHABET.sample(random: SecureRandom) }.join
    self.expires_at ||= 7.days.from_now
  end

  scope :usable, -> { where(expires_at: Time.current..).where("uses_count < max_uses") }

  # 7K2P-9QXM
  def display_code = code.scan(/.{1,4}/).join("-")

  # The new user, or nil when the code is wrong, expired or used up (one answer for all: don't say which).
  # The use is counted in the same UPDATE that checks it, so two sign-ups can't share the last one.
  def self.redeem(code, zalo:, terms_version:)
    invite = usable.find_by(code: code.to_s)
    return unless invite && zalo[:id].present?
    transaction do
      return unless usable.where(id: invite.id).update_all("uses_count = uses_count + 1") == 1
      user = User.create!(name: zalo[:name].presence || "Người dùng Zalo", zalo_id: zalo[:id], role: "user",
        password: User.unknown_password, terms_version:, terms_accepted_at: Time.current)
      PaperTrail.request(whodunnit: user.id) { user.place_memberships.create!(place: invite.place, role: invite.role) }
      user
    end
  end
end
