# Free rooms per place on a Huế calendar day: { "place-slug" => { left:, max_guests: } }.
# Places with no active rooms are omitted.
module Vacancy
  def self.on(date = Date.current)
    busy = Booking.blocking_on(date).pluck(:room_id).to_set
    # ponytail: groups all active rooms in Ruby; move to a SQL GROUP BY if rooms reach thousands
    Room.where(active: true).joins(:place).pluck("places.slug", :id, :max_guests)
      .group_by(&:first)
      .transform_values do |rooms|
        free = rooms.reject { |_, id, _| busy.include?(id) }
        { left: free.size, max_guests: free.map(&:last).max || 0 }
      end
  end
end
