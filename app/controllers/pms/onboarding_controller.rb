# Bắt đầu (#266, board Onboarding.dc.html): the steps after the first login in this browser. Hôm nay sends here once
# (cookie pms_onboarded): Đặt ra màn hình chính and Bật thông báo are per device, so the flag is too.
class Pms::OnboardingController < Pms::BaseController
  def show
    cookies.permanent[:pms_onboarded] = "1"
    @steps = [ "install", ("notif" if WebPush.enabled?), ("setup" if current_place && allowed_to?(:manage, current_place)) ].compact
  end
end
