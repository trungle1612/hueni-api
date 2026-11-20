require "test_helper"

class ApplicationJobTest < ActiveJob::TestCase
  test "job arguments stay out of the logs (#280)" do
    assert_not ApplicationJob.log_arguments
    assert_not SyncCalendarFeedJob.log_arguments
  end

  test "New Relic agent is off without a license key" do
    assert_not NewRelic::Agent.config[:agent_enabled]
  end
end
