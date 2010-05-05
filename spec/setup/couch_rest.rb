require 'couchrest'
require 'delayed/backend/couch_rest'

CouchRest.logger = Delayed::Worker.logger
CouchRest::Server.new.database!('delayed_job_spec')
