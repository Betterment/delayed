module Delayed
  class Plugin
    class_inheritable_accessor :callback_block

    def self.callbacks(&block)
      self.callback_block = block
    end
    
    def initialize
      self.class.callback_block.call(Delayed::Worker.lifecycle) if self.class.callback_block
    end
  end
end