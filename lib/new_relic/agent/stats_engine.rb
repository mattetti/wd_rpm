require 'new_relic/agent/stats_engine/metric_stats'
require 'new_relic/agent/stats_engine/samplers'
require 'new_relic/agent/stats_engine/transactions'
require 'new_relic/agent/stats_engine/gc_profiler'
require 'new_relic/agent/stats_engine/stats_hash'

module NewRelic
  module Agent
    # This class handles all the statistics gathering for the agent
    class StatsEngine
      include MetricStats
      include Samplers
      include Transactions

      def initialize
        # Makes the unit tests happy
        Thread::current[:newrelic_scope_stack] = nil
        @stats_lock = Mutex.new
        @stats_hash = StatsHash.new
        start_sampler_thread
      end

      # All access to the @stats_hash ivar should be funnelled through this
      # method to ensure thread-safety. 
      def with_stats_lock
        @stats_lock.synchronize { yield }
      end
    end
  end
end
