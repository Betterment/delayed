module Delayed
  class Engine < Rails::Engine
    engine_name 'delayed'

    rake_tasks do
      load 'delayed/tasks.rb'
    end
  end
end
