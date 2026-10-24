# Who is signed in and their homestays (#152).
class MiniApp::V1::MeController < MiniApp::V1::BaseController
  def show = render(json: me_json(Current.user))
end
