require "test_helper"

class PlaceImportTest < ActiveSupport::TestCase
  def hueni_places = JSON.parse(file_fixture("homestay.json").read)["places"]

  test "creates new places and overwrites changed fields of existing ones" do
    assert_equal({ created: 1, updated: 1, unchanged: 0 }, Place.import(hueni_places))

    tomo = places(:tomo).reload
    assert_equal "+84 338 268 999", tomo.phone
    assert_equal 4.8, tomo.rating
    assert_equal 16.4603327, tomo.lat
    assert_equal 107.5677355, tomo.lng
    assert_equal "https://www.facebook.com/tomo", tomo.website
    assert_equal "https://hueni.me/images/homestay/tomo-homestay/cover.webp", tomo.cover_image_url
    assert_equal "ChIJZ2Zrp7SnQTERagYjjuo8XN0", tomo.google_place_id

    nha_vuon = Place.find_by!(slug: "nha-vuon-homestay")
    assert_equal "Nhà Vườn Homestay", nha_vuon.name
    assert_nil nha_vuon.phone
  end

  test "re-import with same data changes nothing" do
    Place.import(hueni_places)
    assert_equal({ created: 0, updated: 0, unchanged: 2 }, Place.import(hueni_places))
  end

  test "keeps places missing from the file" do
    Place.import(hueni_places)
    assert Place.exists?(slug: "hiuhill-homestay")
  end
end
