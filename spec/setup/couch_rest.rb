require 'couchrest'
require 'delayed/backend/couch_rest'

Delayed::Backend::CouchRest::Job.use_database CouchRest::Server.new.database!('delayed_job_spec')
