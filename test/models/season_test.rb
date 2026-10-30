require "test_helper"

class SeasonTest < ActiveSupport::TestCase
  test "a season ends on or after its first day and adds a positive whole %" do
    season = places(:tomo).seasons.build(name: " Tết ", from: "2026-02-12", to: "2026-02-04", pct: 0)
    assert_not season.valid?
    assert_equal [ "Đến ngày phải từ ngày bắt đầu trở đi" ], season.errors.full_messages_for(:to)
    assert season.errors[:pct].any?

    season.assign_attributes(to: "2026-02-12", pct: 50)
    assert season.valid?
    assert_equal "Tết", season.name
  end

  test "new homestays start with the Phụ thu list, flexible cancellation and no long-stay discount" do
    place = Place.create!(slug: "moi", name: "Mới")
    assert_equal Surcharge::DEFAULTS.map(&:first), place.surcharges.order(:id).pluck(:name)
    assert_equal [ "flex", false ], [ place.cancel_policy, place.long_stay ]
    assert_not place.update(cancel_policy: "lax")
  end
end
