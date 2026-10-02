# Idempotent. Mock data for local development lives in db/seeds/development.rb; other environments get nothing yet.
env_seeds = Rails.root.join("db/seeds/#{Rails.env}.rb")
load env_seeds if env_seeds.exist?
