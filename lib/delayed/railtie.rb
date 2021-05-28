module Delayed
  class Railtie < Rails::Railtie
    initializer :after_initialize do
      Delayed::Worker.logger ||= Rails.logger
    end

    rake_tasks do
      load 'delayed/tasks.rb'
    end
  end
end
