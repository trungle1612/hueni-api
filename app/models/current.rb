class Current < ActiveSupport::CurrentAttributes
  attribute :session, :api_token # a browser session (/admin) or a Mini App bearer token (/app/v1, #152)

  def user = session&.user || api_token&.user
end
