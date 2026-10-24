# Dịch vụ (#140): a homestay's catalog, set by the owner. Adding one to a booking copies it (BookingCharge),
# so changing or deleting it later never changes a bill.
class Service < ApplicationRecord
  include VndPrice

  belongs_to :place
  has_paper_trail on: %i[create update destroy], only: %i[name price unit], meta: { place_id: :place_id }

  DEFAULTS = [ [ "Nước suối", 15_000, "chai" ], [ "Giặt ủi", 30_000, "kg" ], [ "Thuê xe máy", 150_000, "ngày" ],
    [ "Nhận phòng sớm", 100_000, nil ], [ "Trả phòng muộn", 150_000, nil ] ].freeze

  normalizes :name, :unit, with: ->(value) { value.squish.presence }
  validates :name, presence: true, length: { maximum: 50 }
  # In Ruby: SQLite's case-insensitive compare only folds ASCII ("SUỐI" ≠ "suối").
  validate -> { errors.add(:name, :taken) if place.services.where.not(id:).any? { it.name.casecmp?(name) } }, if: -> { place && name }
  validates :unit, length: { maximum: 20 }
  vnd_price :price
  validates :price, presence: true
end
