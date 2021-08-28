module Delayed
  class Engine < Rails::Engine
    rake_tasks do
      load 'delayed/tasks.rb'
    end
  end
end
