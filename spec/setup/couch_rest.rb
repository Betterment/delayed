require 'couchrest'
require 'delayed/backend/couch_rest'

Delayed::Backend::CouchRest::Job.use_database CouchRest::Server.new.database!('delayed_job_spec')

# try to perform a query to check that we can connect
Delayed::Backend::CouchRest::Job.all