require 'timeout'

module Delayed
  # We inherit from Exception because we want timeouts to bubble up to the
  # worker thread where they can be handled appropriately. (If we inherited from
  # StandardError, jobs are more likely to inadvertently `rescue` it directly.)
  class WorkerTimeout < Exception # rubocop:disable Lint/InheritException
    def message
      seconds = Delayed::Worker.max_run_time.to_i
      "#{super} (Delayed::Worker.max_run_time is only #{seconds} second#{seconds == 1 ? '' : 's'})"
    end
  end

  class FatalBackendError < RuntimeError; end

  class DeserializationError < StandardError; end
end
