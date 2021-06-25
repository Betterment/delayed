require 'rails/generators/base'

module Delayed
  class Generator < Rails::Generators::Base
    source_paths << File.join(File.dirname(__FILE__), 'templates')
  end
end
