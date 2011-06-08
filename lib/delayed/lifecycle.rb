module Delayed
  class Lifecycle    
    def self.set_callback name, *args, &block
      case name
      when :enqueue
        Delayed::Job.set_callback name, *args, &block
      else
        Delayed::Worker.set_callback name, *args, &block
      end
    end
  end
end