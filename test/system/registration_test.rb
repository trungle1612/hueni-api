require "application_system_test_case"

class RegistrationTest < ApplicationSystemTestCase
  test "owner registers with Zalo, an admin approves after calling, the owner logs in" do
    OmniAuth.config.mock_auth[:zalo2] = OmniAuth::AuthHash.new(provider: "zalo2", uid: "zalo-hoa", info: { name: "Hoa Nguyễn" })
    visit new_session_path
    click_button "Đăng ký làm chủ homestay bằng Zalo"
    assert_selector "h1", text: "Đăng ký làm chủ homestay"
    fill_in "Số điện thoại", with: "0905 123 456"
    fill_in "Tên homestay", with: "Hiu Hill Homestay"
    click_button "Gửi đăng ký"
    assert_text "hueni sẽ gọi cho bạn ở số 0905 123 456"

    users(:admin).update!(zalo_id: "zalo-trung")
    log_in_with_zalo "zalo-trung"
    click_link "Người dùng", match: :first
    click_link "Hoa Nguyễn"
    check "Tôi đã xác minh cách khác và ghi trong Ghi chú"
    fill_in "Ghi chú: đã xác minh thế nào? (bắt buộc khi duyệt)", with: "Gọi người quen ở Kim Long"
    accept_confirm { click_button "Tạo tài khoản chủ Hiu Hill Homestay" }
    assert_text "Đã tạo tài khoản cho Hoa Nguyễn"

    Capybara.reset_sessions!
    log_in_with_zalo "zalo-hoa"
    assert_text "Hiu Hill Homestay"
  end

  test "the admin filters the homestay list to correct a misspelled name" do
    places(:hiuhill).update!(name: "Hiu Hill Đồi Thông")
    registration = RegistrationRequest.create!(zalo_id: "zalo-lan", name: "Lan", phone_number: "0905999888", place_name: "Hieu Hil")
    users(:admin).update!(zalo_id: "zalo-trung")
    log_in_with_zalo "zalo-trung"
    visit admin_registration_request_path(registration)
    fill_in "Tìm homestay…", with: "doi thong"
    assert_equal [ "— Chưa có trên hueni —", "Hiu Hill Đồi Thông" ], all("#registration_request_place_id option").map(&:text)
    select "Hiu Hill Đồi Thông", from: "Homestay"
    assert_text "Người đăng ký gõ: \"Hieu Hil\"" # saved on change, no Lưu
    assert_button "Tạo tài khoản chủ Hiu Hill Đồi Thông"
  end
end
