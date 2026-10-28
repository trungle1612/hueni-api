# A homestay's Dịch vụ catalog entry, to add to a booking (POST /bookings/:id/charges).
class MiniApp::ServiceSerializer
  include Alba::Resource

  attributes :id, :name, :price, :unit
end
