require 'couchrest'
require 'delayed/backend/couch_rest'

db = 'delayed_job_spec'
CouchRest::Server.new.database!(db)
Delayed::Backend::CouchRest::Job.db = db
