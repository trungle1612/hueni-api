# The Mini App's Charge: a service on the bill, unit price × qty.
class MiniApp::ChargeSerializer
  include Alba::Resource

  attributes :id, :name, :unit, :amount
  attribute(:price) { it.unit_price }
  attribute(:qty) { it.quantity }
  attribute(:at) { it.created_at }
end
