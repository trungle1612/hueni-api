class Place < ApplicationRecord
  has_many :rooms

  validates :slug, presence: true, uniqueness: true
  validates :name, presence: true
end
