require 'thread'
module NewRelic
  module Agent

    # A worker loop executes a set of registered tasks on a single thread.
    # A task is a proc or block with a specified call period in seconds.
    class WorkerLoop

      # Optional argument duration (in seconds) for how long the worker loop runs
      def initialize(duration=nil)
        @log = log
        @should_run = true
        @next_invocation_time = Time.now
        @period = 60.0
        @deadline = Time.now + duration if duration
      end
      
      # returns a class-level memoized mutex to make sure we don't run overlapping
      def lock
        @@lock ||= Mutex.new
      end
      
      # a helper to access the NewRelic::Control.instance.log
      def log
        NewRelic::Control.instance.log
      end
      
      # Run infinitely, calling the registered tasks at their specified
      # call periods.  The caller is responsible for creating the thread
      # that runs this worker loop.  This will run the task immediately.
      def run(period=nil, &block)
        @period = period if period
        @next_invocation_time = (Time.now + @period)
        @task = block
        while keep_running do
          while @now < @next_invocation_time
            # sleep until this next task's scheduled invocation time
            sleep_time = @next_invocation_time - @now
            sleep sleep_time if sleep_time > 0
            @now = Time.now
          end
          run_task if keep_running
        end
      end
      
      def keep_running
        @now = Time.now
        @should_run && (!@deadline || @now < @deadline)
      end
      
      def stop
        @should_run = false
      end
      
      # Executes the block given to the worker loop, and handles many
      # possible errors. Also updates the execution time so that the
      # next run occurs on schedule, even if we execute at some odd time
      def run_task
        begin
          lock.synchronize do
            @task.call
          end
        rescue ServerError => e
          log.debug "Server Error: #{e}"
        rescue NewRelic::Agent::ForceRestartException, NewRelic::Agent::ForceDisconnectException
          # blow out the loop
          raise
        rescue RuntimeError => e
          # This is probably a server error which has been logged in the server along
          # with your account name.
          log.error "Error running task in worker loop, likely a server error (#{e})"
          log.debug e.backtrace.join("\n")
        rescue Timeout::Error, NewRelic::Agent::ServerConnectionException
          # Want to ignore these because they are handled already
        rescue SystemExit, NoMemoryError, SignalException
          raise
        rescue => e
          # Don't blow out the stack for anything that hasn't already propagated
          log.error "Error running task in Agent Worker Loop '#{e}': #{e.backtrace.first}"
          log.debug e.backtrace.join("\n")
        end
        now = Time.now
        while @next_invocation_time <= now && @period > 0
          @next_invocation_time += @period
        end
      end
    end
  end
end
