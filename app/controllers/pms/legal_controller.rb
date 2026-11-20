# Điều khoản và quyền riêng tư (#236): the texts of config/legal.yml, and the version this user agreed to (#206).
# Public (#271): linked from Giới thiệu and the sitemap; the consent line only for a signed-in user.
class Pms::LegalController < Pms::BaseController
  LEGAL = YAML.load_file(Rails.root.join("config/legal.yml")).freeze

  allow_unauthenticated_access

  def show
    resume_session
    @doc = params[:doc].presence_in(%w[terms privacy]) || "terms"
  end
end
