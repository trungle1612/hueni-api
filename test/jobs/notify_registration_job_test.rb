require "test_helper"

class NotifyRegistrationJobTest < ActiveJob::TestCase
  setup do
    @registration = RegistrationRequest.create!(zalo_id: "zalo-hoa", name: "Hoa Nguyễn", phone_number: "0905123456", place_name: "Hoa Sen Homestay")
    @url = "https://api.hueni.me/admin/registration_requests/#{@registration.id}"
  end

  def with_telegram(token: "TOKEN", chat_id: "-100123")
    old = ENV.values_at("TELEGRAM_BOT_TOKEN", "TELEGRAM_CHAT_ID")
    ENV["TELEGRAM_BOT_TOKEN"], ENV["TELEGRAM_CHAT_ID"] = token, chat_id
    yield
  ensure
    ENV["TELEGRAM_BOT_TOKEN"], ENV["TELEGRAM_CHAT_ID"] = old
  end

  test "posts name, homestay and the admin link, never the phone or Zalo id" do
    sent = stub_request(:post, "https://api.telegram.org/botTOKEN/sendMessage").with { |request|
      URI.decode_www_form(request.body).to_h == { "chat_id" => "-100123", "text" => "Yêu cầu đăng ký mới: Hoa Nguyễn — Hoa Sen Homestay\n#{@url}" }
    }
    with_telegram { NotifyRegistrationJob.perform_now(@registration, @url) }
    assert_requested sent
  end

  test "does nothing without a bot token or chat id" do
    with_telegram(token: nil) { NotifyRegistrationJob.perform_now(@registration, @url) }
    with_telegram(chat_id: "") { NotifyRegistrationJob.perform_now(@registration, @url) }
    assert_not_requested :post, %r{api\.telegram\.org}
  end

  test "a Telegram error is retried" do
    stub_request(:post, "https://api.telegram.org/botTOKEN/sendMessage").to_return(status: 502)
    with_telegram do
      assert_enqueued_with(job: NotifyRegistrationJob) { NotifyRegistrationJob.perform_now(@registration, @url) }
    end
  end
end
