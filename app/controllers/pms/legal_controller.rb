# Điều khoản và quyền riêng tư (#236): the texts of config/legal.yml, and the version this user agreed to (#206).
class Pms::LegalController < Pms::BaseController
  LEGAL = YAML.load_file(Rails.root.join("config/legal.yml")).freeze

  def show
    @doc = params[:doc].presence_in(%w[terms privacy]) || "terms"
  end
end
