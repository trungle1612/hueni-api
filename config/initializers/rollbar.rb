# Error reporting (#215). Sends nothing unless ROLLBAR_ACCESS_TOKEN is set (production only).
Rollbar.configure do |config|
  config.access_token = ENV["ROLLBAR_ACCESS_TOKEN"]
  config.enabled = config.access_token.present?
  config.environment = Rails.env
  config.code_version = ENV["KAMAL_VERSION"] # git SHA, set by Kamal on the container

  # Rollbar skips Regexps (and escapes the ones it reads from Rails), so /\Aq\z/ goes in as :q.
  # Its param match is partial: :q also hides other keys with a "q" (quantity, X-Request-Id).
  config.scrub_fields |= Rails.application.config.filter_parameters.grep_v(Regexp) + [ :q ]

  # 4xx are not errors.
  config.exception_level_filters.merge!(
    "ActiveRecord::RecordNotFound" => "ignore",
    "AbstractController::ActionNotFound" => "ignore",
    "ActionController::RoutingError" => "ignore"
  )
end

# A job that still fails after its retry_on (discard_on ones never get here). Job arguments are not sent:
# they carry guest names and records.
Rails.application.config.solid_queue.on_thread_error = ->(error) do
  Rails.error.report(error, handled: false)
  Rollbar.error(error)
end
