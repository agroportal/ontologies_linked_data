require 'minitest/autorun'
require_relative '../../lib/ontologies_linked_data'

# ActiveSupport 7+ core extensions need `require "active_support"` first.
# Without it Time.zone raises NameError, which kills ncbo_cron's
# rufus-scheduler on start.
class TestActiveSupport < Minitest::Test
  def test_time_zone
    Time.zone
    pass
  end
end
