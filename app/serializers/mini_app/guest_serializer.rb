# Hồ sơ khách (#165) in the list: booking_id = the guest's newest booking, which opens the profile (never the phone).
class MiniApp::GuestSerializer
  include Alba::Resource

  attribute(:booking_id) { it.latest.id }
  attribute(:name) { it.latest.guest_name }
  attribute(:phone) { it.latest.guest_phone }
  attribute(:visits) { it.visits.size }
  attribute(:returning) { it.returning? }
  attribute(:first_stay) { it.bookings.last.start_date }
  attribute(:last_stay) { it.latest.start_date }
  attributes :flag
end
