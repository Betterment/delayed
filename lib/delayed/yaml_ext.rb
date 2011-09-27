# These extensions allow properly serializing and autoloading of
# Classes, Modules and Structs

require 'yaml'

if YAML::ENGINE.syck?
  require File.expand_path('../syck_ext', __FILE__)
else
  require File.expand_path('../psych_ext', __FILE__)
end
