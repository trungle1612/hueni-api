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

  # The single access rule for admin code: look records up only through these.
  # Out-of-scope `find` raises RecordNotFound, which Rails renders as 404.
  def accessible_places = admin? ? Place.all : Place.where(id: place_memberships.select(:place_id))
  def accessible_rooms = Room.where(place_id: accessible_places.select(:id))
  def accessible_calendar_feeds = CalendarFeed.where(room_id: accessible_rooms.select(:id))
  def accessible_bookings = Booking.where(room_id: accessible_rooms.select(:id))
end
