# These extensions allow properly serializing and autoloading of
# Classes, Modules and Structs

if RUBY_VERSION < '1.9.0'
  require 'syck'
  require File.expand_path('../syck_ext', __FILE__)
else
  require 'psych'
  require File.expand_path('../psych_ext', __FILE__)
end
require 'yaml'
