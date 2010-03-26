require 'dm-core'

DataMapper.logger = ActiveRecord::Base.logger
DataMapper.setup(:default, "sqlite3::memory:")
