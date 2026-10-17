require "test_helper"

class RegistrationRequestTest < ActiveSupport::TestCase
  def request_for(place: nil, **attrs)
    RegistrationRequest.create!({ zalo_id: "zalo-hoa", zalo_name: "Hoa Zalo", name: "Hoa Nguyễn",
      phone_number: "0905 123 456", place:, place_name: place&.name || "Nhà Mơ Kim Long" }.merge(attrs))
  end

  test "normalizes the phone; requires name, phone and homestay; the maps link must be http(s)" do
    assert_equal "0905123456", request_for.phone_number
    registration = RegistrationRequest.new(zalo_id: "z", name: "", phone_number: "123", place_name: "", maps_url: "javascript:alert(1)")
    assert_not registration.valid?
    assert_equal %i[maps_url name phone_number place_name], registration.errors.attribute_names.sort
  end

  test "a phone that already has an account is refused" do
    registration = RegistrationRequest.new(zalo_id: "z", name: "X", phone_number: "+84 912 345 678", place_name: "X") # Chị Lan
    assert_not registration.valid?
    assert_includes registration.errors[:base], "Số điện thoại này đã có tài khoản. Liên hệ quản trị viên."
  end

  test "one pending request per Zalo account" do
    first = request_for
    assert_raises(ActiveRecord::RecordNotUnique) { request_for(phone_number: "0905000111") }
    first.update!(status: "rejected")
    assert request_for(phone_number: "0905000111").pending?
  end

  test "approve creates a Zalo-linked account, owner of an ownerless homestay" do
    registration = request_for(place: places(:hiuhill))
    assert registration.approve!(by: users(:admin))
    user = registration.user
    assert_equal [ "Hoa Nguyễn", "0905123456", "zalo-hoa", "user" ], [ user.name, user.phone_number, user.zalo_id, user.role ]
    assert_equal "owner", user.role_at(places(:hiuhill))
    assert_not user.authenticate("password123")
    assert registration.approved?
    assert_equal users(:admin), registration.decided_by
    assert registration.decided_at
  end

  test "approve without a homestay creates only the account" do
    registration = request_for
    assert registration.approve!(by: users(:admin))
    assert_empty registration.user.place_memberships
  end

  test "approve never makes anyone owner of a homestay that has one, and saves nothing" do
    registration = request_for(place: places(:tomo))
    assert_no_difference [ "User.count", "PlaceMembership.count" ] do
      assert_not registration.approve!(by: users(:admin))
    end
    assert_equal [ "tomo homestay vừa có chủ. Không tạo tài khoản." ], registration.errors[:base]
    assert registration.reload.pending?
  end

  test "approve re-checks phone and Zalo, and refuses a decided request" do
    registration = request_for
    taken = User.create!(name: "X", phone_number: "0905123456", password: "password123")
    assert_not registration.approve!(by: users(:admin))
    assert_equal [ "Số điện thoại này đã có tài khoản." ], registration.errors[:base]

    taken.update!(phone_number: "0905999999", zalo_id: "zalo-hoa")
    assert_not registration.approve!(by: users(:admin))
    assert_equal [ "Zalo này đã liên kết với tài khoản khác." ], registration.errors[:base]

    registration.update!(status: "rejected")
    assert_not registration.approve!(by: users(:admin))
    assert_equal [ "Yêu cầu đã được xử lý." ], registration.errors[:base]
  end

  test "reject keeps the request with who and when, once" do
    registration = request_for
    assert registration.reject!(by: users(:admin))
    assert registration.rejected?
    assert_equal users(:admin), registration.decided_by
    assert_not registration.reject!(by: users(:admin))
  end

  test "homestay_name and place_owners" do
    assert_equal [ "tomo homestay", [ users(:owner) ] ], request_for(place: places(:tomo)).then { [ it.homestay_name, it.place_owners ] }
    unlisted = request_for(zalo_id: "zalo-2", phone_number: "0905000222")
    assert_equal [ "Nhà Mơ Kim Long", [] ], [ unlisted.homestay_name, unlisted.place_owners ]
  end
end
