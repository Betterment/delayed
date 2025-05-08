module Delayed
  module Plugins
    class Connection < Plugin
      callbacks do |lifecycle|
        lifecycle.around(:thread) do |worker, &block|
          Job.connection_pool.with_connection do
            block.call(worker)
          end
        end
      end
    end
  end
end
