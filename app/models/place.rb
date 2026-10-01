class Place < ApplicationRecord
  has_many :rooms

  after_commit { Vacancy.bust }

  validates :slug, presence: true, uniqueness: true
  validates :name, presence: true
end
