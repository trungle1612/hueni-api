# The Mini App's Payment: amount < 0 = a refund.
class MiniApp::PaymentSerializer
  include Alba::Resource

  attributes :id, :kind, :note
  attribute(:amount) { it.signed_amount }
  attribute(:method) { it.payment_method }
  attribute(:at) { it.created_at }
  attribute(:by) { it.user&.name }
end
