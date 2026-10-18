require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  def zalo_login(uid = "zalo-hoa", name: "Hoa Nguyễn")
    mock_zalo(uid, name:)
    post "/auth/zalo2"
    follow_redirect! # → callback
    follow_redirect! # → /dang-ky
  end

  def submit(**fields)
    post registration_path, params: { registration_request: { name: "Hoa Nguyễn", phone_number: "0905 123 456",
      place_name: "Hiu Hill Homestay", maps_url: "" }.merge(fields) }
  end

  test "without a Zalo login, or after 30 minutes, back to the login page" do
    get registration_path
    assert_redirected_to new_session_path
    assert_equal "Phiên đăng ký hết hạn. Đăng nhập Zalo lại.", flash[:alert]
    submit
    assert_redirected_to new_session_path

    zalo_login
    travel 31.minutes
    submit
    assert_redirected_to new_session_path
    assert_equal 0, RegistrationRequest.count
  end

  test "form is prefilled from Zalo, suggests hueni homestays and points staff to their owner" do
    zalo_login
    assert_response :success
    assert_select "input[name='registration_request[name]'][value=?]", "Hoa Nguyễn"
    assert_select "datalist#places option[value=?]", "Hiu Hill Homestay"
    assert_select "body", text: /Bạn là nhân viên\? Nhờ chủ homestay thêm bạn ở mục Thành viên/
    assert_select "a[href=?]", "tel:#{RegistrationsController::HELP_PHONE}"
  end

  test "submitting saves a pending request with the Zalo id from the session, matched to a hueni homestay, and notifies" do
    zalo_login
    assert_enqueued_with(job: NotifyRegistrationJob) do
      submit(zalo_id: "zalo-someone-else")
    end
    registration = RegistrationRequest.sole
    assert_equal [ "zalo-hoa", "Hoa Nguyễn", "0905123456", places(:hiuhill), "pending" ],
      [ registration.zalo_id, registration.zalo_name, registration.phone_number, registration.place, registration.status ]
    assert_redirected_to registration_path
    follow_redirect!
    assert_select "body", text: /hueni sẽ gọi cho bạn ở số 0905 123 456 trong 1–2 ngày để xác nhận/
    assert_select "body", text: /Đang chờ duyệt/
    assert_select "input[name='registration_request[name]']", 0
  end

  test "an unlisted homestay keeps the typed name and maps link" do
    zalo_login
    submit(place_name: "Nhà Mơ Kim Long", maps_url: "https://maps.app.goo.gl/abc")
    registration = RegistrationRequest.sole
    assert_nil registration.place
    assert_equal [ "Nhà Mơ Kim Long", "https://maps.app.goo.gl/abc" ], [ registration.place_name, registration.maps_url ]
  end

  test "an ambiguous name stays unlisted" do
    Place.create!(slug: "hiuhill-2", name: "Hiu Hill Homestay")
    zalo_login
    submit
    assert_nil RegistrationRequest.sole.place
  end

  test "a taken phone or bad input re-renders the form and saves nothing" do
    zalo_login
    submit(phone_number: "0912 345 678") # Chị Lan
    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /Số điện thoại này đã có tài khoản\. Liên hệ quản trị viên\./
    submit(maps_url: "javascript:alert(1)", name: "", phone_number: "0905 12")
    assert_response :unprocessable_entity
    assert_select "#maps_url_error", text: /Link Google Maps/
    assert_select "input[aria-invalid=true][aria-describedby='phone_hint phone_number_error'].input-error[name='registration_request[phone_number]']"
    assert_select "#phone_number_error", text: "Số điện thoại cần đủ 10 số, ví dụ 0912 345 678"
    assert_select "input[aria-invalid=true][aria-describedby=name_error][name='registration_request[name]']"
    assert_equal 0, RegistrationRequest.count
  end

  test "a second submit while pending shows the status, not an error" do
    zalo_login
    submit
    submit(phone_number: "0905000111")
    assert_redirected_to registration_path
    assert_equal 1, RegistrationRequest.count
  end

  test "a rejected request can be sent again" do
    zalo_login
    submit
    RegistrationRequest.sole.update!(status: "rejected")
    get registration_path
    assert_select "[role=alert]", text: /Yêu cầu trước chưa được duyệt\./
    assert_select "input[name='registration_request[phone_number]'][value=?]", "0905123456"
    assert_select "input[name='registration_request[place_name]'][value=?]", "Hiu Hill Homestay"
    submit
    assert_equal 2, RegistrationRequest.count
  end

  test "after approval, the form and the status page send the owner to Zalo login" do
    zalo_login
    submit
    RegistrationRequest.sole.tap { it.update!(admin_note: "Đã gọi") }.approve!(by: users(:admin))
    get registration_path
    assert_redirected_to new_session_path
    assert_equal "Tài khoản đã được duyệt. Bấm Đăng nhập bằng Zalo.", flash[:notice]
    assert_nil session[:registration]
  end

  test "submitting after approval also goes to Zalo login" do
    zalo_login
    users(:admin).update!(zalo_id: "zalo-hoa")
    submit
    assert_redirected_to new_session_path
    assert_equal "Tài khoản đã được duyệt. Bấm Đăng nhập bằng Zalo.", flash[:notice]
    assert_equal 0, RegistrationRequest.count
  end

  test "the pending status page offers to correct the request, not a login that would loop back here" do
    zalo_login
    submit
    follow_redirect!
    assert_select "h1", "Đã gửi đăng ký"
    assert_select "form[action='/auth/zalo2']", 0
    assert_select "a[href=?]", registration_path(sua: 1), text: "Sai thông tin? Sửa lại"
  end

  test "a pending request is corrected in place" do
    zalo_login
    submit
    get registration_path(sua: 1)
    assert_select "input[name='registration_request[phone_number]'][value=?]", "0905123456"
    assert_no_enqueued_jobs do
      patch registration_path, params: { registration_request: { name: "Hoa", phone_number: "0905 000 111",
        place_name: "Nhà Mơ Kim Long", maps_url: "maps.app.goo.gl/abc", zalo_id: "zalo-x" } }
    end
    assert_redirected_to registration_path
    registration = RegistrationRequest.sole
    assert_equal [ "Hoa", "0905000111", nil, "Nhà Mơ Kim Long", "https://maps.app.goo.gl/abc", "zalo-hoa", "pending" ],
      [ registration.name, registration.phone_number, registration.place, registration.place_name, registration.maps_url,
        registration.zalo_id, registration.status ]

    patch registration_path, params: { registration_request: { phone_number: "0912 345 678" } } # Chị Lan
    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /Số điện thoại này đã có tài khoản/
    assert_equal "0905000111", registration.reload.phone_number
  end

  test "a decided request can't be edited" do
    zalo_login
    submit
    RegistrationRequest.sole.update!(status: "rejected")
    patch registration_path, params: { registration_request: { phone_number: "0905000111" } }
    assert_redirected_to registration_path
    assert_equal "0905123456", RegistrationRequest.sole.phone_number
  end

  test "Thoát clears the Zalo session" do
    zalo_login
    delete registration_path
    assert_redirected_to new_session_path
    get registration_path
    assert_redirected_to new_session_path
  end
end
