# Khoản chi tiền mặt from the till (#167). Whoever wrote it, or an owner, can change or delete it until the shift
# is closed (Shift#open?); after that it is part of a close's expected cash.
class CashExpense < ApplicationRecord
  include VndPrice

  belongs_to :place
  belongs_to :user, optional: true
  has_paper_trail meta: { place_id: :place_id }

  vnd_price :amount
  validates :amount, presence: true, numericality: { greater_than: 0 }
  normalizes :reason, with: ->(value) { value.squish.presence }
  validates :reason, presence: true, length: { maximum: 200 }

  def closed? = place.shift_closes.where(created_at: created_at..).exists?
end
