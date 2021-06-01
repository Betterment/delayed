module Delayed
  class Railtie < Rails::Railtie
    rake_tasks do
      load 'delayed/tasks.rb'
    end
  end
end
