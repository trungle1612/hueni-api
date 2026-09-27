require "test_helper"

class PlaceTest < ActiveSupport::TestCase
  test "requires slug and name" do
    place = Place.new
    assert_not place.valid?
    assert_includes place.errors.attribute_names, :slug
    assert_includes place.errors.attribute_names, :name
  end

  test "slug is unique" do
    place = Place.new(slug: places(:tomo).slug, name: "Other")
    assert_not place.valid?
    assert_includes place.errors.attribute_names, :slug
  end

  test "db enforces unique slug" do
    assert_raises(ActiveRecord::RecordNotUnique) do
      Place.new(slug: places(:tomo).slug, name: "Other").save(validate: false)
    end
  end

  test "has rooms" do
    assert_equal %w[Garden Limdim], places(:tomo).rooms.pluck(:name).sort
  end
end
