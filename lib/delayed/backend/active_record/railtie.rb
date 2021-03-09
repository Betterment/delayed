module Delayed
  module Backend
    module ActiveRecord
      class Railtie < ::Rails::Railtie
        config.after_initialize do
          require "delayed/backend/active_record"
          Delayed::Worker.backend = :active_record
          Delayed::Worker.plugins << Delayed::Backend::ActiveRecord::ConnectionPlugin
        end
      end
    end
  end
end
