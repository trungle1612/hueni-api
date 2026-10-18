# Owner self-registration: a Zalo login that matched no account (ZaloSessionsController) → /dang-ky
# (RegistrationsController) → an admin calls the homestay to verify → approve! creates the account,
# already linked to that Zalo. zalo_id comes from the Zalo login, never from the form.
class RegistrationRequest < ApplicationRecord
  belongs_to :place, optional: true
  belongs_to :decided_by, class_name: "User", optional: true
  belongs_to :user, optional: true

  normalizes :phone_number, with: ->(phone) { phone.gsub(/\D/, "").sub(/\A84(?=\d{9}\z)/, "0") }
  # Links copied from the Maps app often come without "https://".
  normalizes :maps_url, with: ->(url) { url.strip.presence&.sub(%r{\A(?![a-z][a-z0-9+.-]*:)}i, "https://") }

  enum :status, { pending: "pending", approved: "approved", rejected: "rejected" }, validate: true

  validates :zalo_id, :name, :place_name, presence: true
  validates :name, :place_name, length: { maximum: 100 }
  validates :maps_url, length: { maximum: 500 }
  validates :phone_number, presence: true, format: { with: /\A0\d{9}\z/, allow_blank: true, message: "cần đủ 10 số, ví dụ 0912 345 678" }
  validates :maps_url, format: { with: %r{\Ahttps?://\S+\z}i, allow_blank: true }
  validate :phone_number_free, if: :will_save_change_to_phone_number?

  def homestay_name = place&.name || place_name
  # The admin verifies by calling the homestay's number on hueni. Without one, the note must say how it was verified.
  def verifiable? = place&.phone.present?
  def place_owners = place ? place.place_memberships.owner.includes(:user).map(&:user) : []

  # Re-checks what the admin saw: the request may be days old. Never makes anyone owner
  # of a homestay that already has one.
  def approve!(by:)
    transaction do
      reload
      return refuse("Yêu cầu đã được xử lý.") unless pending?
      return refuse("Số điện thoại này đã có tài khoản.") if User.exists?(phone_number:)
      return refuse("Zalo này đã liên kết với tài khoản khác.") if User.exists?(zalo_id:)
      return refuse("#{place.name} vừa có chủ. Không tạo tài khoản.") if place_owners.any?
      return refuse("Không có SĐT trên hueni để gọi: ghi cách đã xác minh vào Ghi chú.") if !verifiable? && admin_note.blank?

      new_user = User.create!(name:, phone_number:, zalo_id:, role: "user", password: User.unknown_password)
      new_user.place_memberships.create!(place:, role: "owner") if place
      update!(status: "approved", user: new_user, decided_by: by, decided_at: Time.current)
    end
    true
  end

  def reject!(by:)
    transaction do
      reload
      return refuse("Yêu cầu đã được xử lý.") unless pending?
      update!(status: "rejected", decided_by: by, decided_at: Time.current)
    end
    true
  end

  private
    def refuse(message)
      errors.clear
      errors.add(:base, message)
      false
    end

    def phone_number_free
      errors.add(:base, "Số điện thoại này đã có tài khoản. Liên hệ quản trị viên.") if User.exists?(phone_number:)
    end
end
