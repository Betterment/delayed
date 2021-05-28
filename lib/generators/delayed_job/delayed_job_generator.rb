require 'rails/generators/base'

class DelayedJobGenerator < Rails::Generators::Base
  source_paths << File.join(File.dirname(__FILE__), 'templates')
end
