class Place < ApplicationRecord
  has_many :rooms
  has_many :place_memberships, dependent: :destroy
  has_many :users, through: :place_memberships

  after_commit { Vacancy.bust }

  validates :slug, presence: true, uniqueness: true
  validates :name, presence: true

  # Upserts places from hueni's homestay.json "places" array, keyed by slug. Never deletes.
  def self.import(hueni_places)
    counts = { created: 0, updated: 0, unchanged: 0 }
    transaction do
      hueni_places.each do |hp|
        place = find_or_initialize_by(slug: hp.fetch("id"))
        place.assign_attributes(
          name: hp.fetch("name"),
          address: hp["address"],
          phone: hp["phone"],
          rating: hp["rating"],
          lat: hp.dig("coordinates", "lat"),
          lng: hp.dig("coordinates", "lng"),
          website: hp["website"],
          cover_image_url: hp["coverImage"],
          google_place_id: hp["place_id"]
        )
        counts[place.new_record? ? :created : place.changed? ? :updated : :unchanged] += 1
        place.save!
      end
    end
    counts
  end
end
