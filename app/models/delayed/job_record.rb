module Delayed
  class JobRecord < ::ActiveRecord::Base
    self.abstract_class = true
  end
end
