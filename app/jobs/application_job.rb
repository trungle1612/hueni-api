class ApplicationJob < ActiveJob::Base
  # Job arguments carry guest names and records: keep them out of the logs (forwarded to New Relic, #280).
  self.log_arguments = false

  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError
end
