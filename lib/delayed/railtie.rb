require 'delayed_job'
require 'rails'

module Delayed
  class Railtie < Rails::Railtie
    initializer :after_initialize do
      Delayed::Worker.guess_backend
    end

    rake_tasks do
      load 'delayed/tasks.rb'
    end
  end
end
