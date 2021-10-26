module Delayed
  module Runnable
    def start
      trap('TERM') { quit! }
      trap('INT') { quit! }

      say "Starting #{self.class.name}"

      Delayed.lifecycle.run_callbacks(:execute, nil) do
        loop do
          run!
          break if stop?
        end
      end
    ensure
      on_exit!
    end

    private

    def on_exit!; end

    def interruptable_sleep(seconds)
      pipe[0].wait_readable(seconds)
    end

    def stop
      pipe[1].close
    end

    def stop?
      pipe[1].closed?
    end

    def quit!
      Thread.new { say 'Exiting...' }.tap do |t|
        stop
        t.join
      end
    end

    def pipe
      @pipe ||= IO.pipe
    end
  end
end
