class User < ApplicationRecord
  ROLE_LABELS = { "admin" => "Quản trị viên", "owner" => "Chủ homestay" }.freeze

  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :place_memberships, dependent: :destroy
  has_many :places, through: :place_memberships

  # Stored as 10 digits starting with 0: spaces/dots/dashes dropped, +84 / 84 prefix turned into 0.
  normalizes :phone_number, with: ->(phone) { phone.gsub(/\D/, "").sub(/\A84(?=\d{9}\z)/, "0") }

  enum :role, { admin: "admin", owner: "owner" }, validate: true

  validates :name, presence: true
  validates :phone_number, presence: true, uniqueness: true, format: { with: /\A0\d{9}\z/, allow_blank: true }
  validates :password, length: { minimum: 8 }, allow_nil: true

  def self.generate_password = SecureRandom.base58(12) # no 0/O/I/l look-alikes

  def role_label = ROLE_LABELS.fetch(role)

  def initial = name.to_s.first.to_s.upcase

  # The single access rule for admin code: look records up only through these.
  # Out-of-scope `find` raises RecordNotFound, which Rails renders as 404.
  def accessible_places = admin? ? Place.all : Place.where(id: place_memberships.select(:place_id))
  def accessible_rooms = Room.where(place_id: accessible_places.select(:id))
  def accessible_calendar_feeds = CalendarFeed.where(room_id: accessible_rooms.select(:id))
  def accessible_bookings = Booking.where(room_id: accessible_rooms.select(:id))
end
