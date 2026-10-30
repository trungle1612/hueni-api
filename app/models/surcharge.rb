# Phụ thu theo khách (#163): extra guests' prices the owner shows guests (price 0 = Miễn phí). Display only: never
# added to a bill by itself; the desk adds a Dịch vụ when it charges one.
class Surcharge < ApplicationRecord
  include VndPrice

  belongs_to :place
  has_paper_trail on: %i[create update destroy], only: %i[name price unit], meta: { place_id: :place_id }

  DEFAULTS = [ [ "Người lớn thêm", 150_000, "đêm" ], [ "Trẻ 6 – 11 tuổi", 75_000, "đêm" ], [ "Trẻ dưới 6 tuổi", 0, nil ] ].freeze

  normalizes :name, :unit, with: ->(value) { value.squish.presence }
  validates :name, presence: true, length: { maximum: 50 }
  validate -> { errors.add(:name, :taken) if place.surcharges.where.not(id:).any? { it.name.casecmp?(name) } }, if: -> { place && name }
  validates :unit, length: { maximum: 20 }
  vnd_price :price
  validates :price, presence: true
end
