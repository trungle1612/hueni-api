require "test_helper"

# Cài đặt cơ sở in the PWA (#244): Tài khoản chuyển khoản and Dịch vụ, owners only.
class Pms::SettingsTest < ActionDispatch::IntegrationTest
  def staff!
    places(:tomo).place_memberships.create!(user: users(:admin), role: "staff")
    log_in users(:admin)
  end

  test "owner sets the bank account; it shows on Thu tiền" do
    log_in users(:owner)
    get pms_more_path
    assert_select "main a[href=?]", pms_settings_path, text: /Cài đặt cơ sở/
    get pms_settings_path
    assert_response :success
    assert_select "header", text: /Cài đặt cơ sở\s*tomo homestay/

    patch pms_settings_bank_path, params: { place: { bank_name: " Vietcombank ", bank_account: "0123456789", bank_holder: "NGUYEN THI LAN" } }
    assert_redirected_to pms_settings_path
    follow_redirect!
    assert_select ".pms-toast", text: "Đã lưu tài khoản chuyển khoản"
    assert_equal [ "Vietcombank", "0123456789", "NGUYEN THI LAN" ], places(:tomo).reload.values_at(:bank_name, :bank_account, :bank_holder)

    get pms_booking_path(bookings(:limdim_confirmed))
    assert_select "#bank", text: /Vietcombank · 0123456789\s*NGUYEN THI LAN/

    patch pms_settings_bank_path, params: { place: { bank_account: "1" * 31 } }
    assert_response :unprocessable_entity
    assert_select "#bank_account_error"
    assert_equal "0123456789", places(:tomo).reload.bank_account
  end

  test "owner adds, edits and removes a Dịch vụ; the model's refusals shown" do
    log_in users(:owner)
    post pms_services_path, params: { service: { name: "Thuê xe máy", price: "150k", unit: "ngày" } }
    follow_redirect!
    assert_select ".pms-toast", text: "Đã thêm dịch vụ Thuê xe máy"
    service = places(:tomo).services.find_by!(name: "Thuê xe máy")
    assert_equal 150_000, service.price
    assert_select "##{dom_id(service)}", text: /Thuê xe máy\s*150.000đ \/ ngày/
    assert_select "##{dom_id(service, :sheet)} form[action=?]", pms_service_path(service)

    post pms_services_path, params: { service: { name: "thuê xe máy", price: "1" } }
    follow_redirect!
    assert_select "[role=alert]", text: /Tên dịch vụ/
    assert_equal 1, places(:tomo).services.count

    patch pms_service_path(service), params: { service: { name: "Thuê xe máy", price: "120.000", unit: "" } }
    assert_equal [ 120_000, nil ], service.reload.values_at(:price, :unit)

    delete pms_service_path(service)
    follow_redirect!
    assert_select ".pms-toast", text: /Đã xoá dịch vụ Thuê xe máy/
    assert_not Service.exists?(service.id)
  end

  test "staff get Bạn chưa có quyền" do
    service = places(:tomo).services.create!(name: "Nước", price: 10_000)
    staff!
    get pms_more_path
    assert_select "main a[href=?]", pms_settings_path, count: 0
    get pms_settings_path
    assert_response :forbidden
    assert_select "main", text: /Bạn chưa có quyền/
    patch pms_settings_bank_path, params: { place: { bank_name: "X" } }
    assert_response :forbidden
    post pms_services_path, params: { service: { name: "Giặt", price: 1 } }
    assert_response :forbidden
    patch pms_service_path(service), params: { service: { price: 1 } }
    assert_response :forbidden
    delete pms_service_path(service)
    assert_response :forbidden
    assert_nil places(:tomo).reload.bank_name
    assert_equal [ "Nước", 10_000 ], service.reload.values_at(:name, :price)
  end

  test "another owner's service is 404" do
    service = places(:hiuhill).services.create!(name: "Nước", price: 10_000)
    log_in users(:owner)
    patch pms_service_path(service), params: { service: { price: 1 } }
    assert_response :not_found
    delete pms_service_path(service)
    assert_response :not_found
    assert Service.exists?(service.id)
  end
end
