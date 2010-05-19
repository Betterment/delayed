# Make sure this file does not get required manually
module Autoloaded
  class Struct < ::Struct.new(nil)
    def perform
    end
  end
end