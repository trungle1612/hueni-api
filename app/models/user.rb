class User < ApplicationRecord
  ROLE_LABELS = { "admin" => "Quản trị viên", "owner" => "Chủ homestay" }.freeze

  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :place_memberships, dependent: :destroy
  has_many :places, through: :place_memberships

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  enum :role, { admin: "admin", owner: "owner" }, validate: true

  validates :name, presence: true
  validates :email_address, presence: true, uniqueness: true
  validates :password, length: { minimum: 8 }, allow_nil: true

  def role_label = ROLE_LABELS.fetch(role)

  def initial = name.to_s.first.to_s.upcase
end
