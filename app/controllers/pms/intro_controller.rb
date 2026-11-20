# Giới thiệu (#271, board LandingB.dc.html): the public page for owners who hear about hueni (Facebook groups, Google).
# Signed-in users see it too, with Vào app instead of Đăng nhập. No public cache: the Zalo buttons carry a CSRF token.
class Pms::IntroController < Pms::BaseController
  allow_unauthenticated_access

  def show
    resume_session
  end
end
