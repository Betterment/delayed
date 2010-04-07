require 'delayed_job'
require 'rails'

module Delayed
  class Railtie < Rails::Railtie
    initializer :after_initialize do
      Delayed::Worker.backend ||= if defined?(ActiveRecord)
        :active_record
      elsif defined?(MongoMapper)
        :mongo_mapper
      else
        Delayed::Worker.logger.warn "Could not decide on a backend, defaulting to active_record"
        :active_record
      end
    end
  end
end
