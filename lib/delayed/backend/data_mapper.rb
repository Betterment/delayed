require 'dm-core'
require 'dm-observer'
require 'dm-aggregates'

module DataMapper
  module Resource
    module ClassMethods
      def load_for_delayed_job(id)
        find!(id)
      end
    end

    module InstanceMethods
      def dump_for_delayed_job
        "#{self.class};#{id}"
      end
    end
  end
end

module Delayed
  module Backend
    module DataMapper
      class Job
        include ::DataMapper::Resource
        include Delayed::Backend::Base
        
        storage_names[:default] = 'delayed_jobs'
        
        property :id,          Serial
        property :priority,    Integer, :default => 0
        property :attempts,    Integer, :default => 0
        property :handler,     String
        property :run_at,      Time
        property :locked_at,   Time
        property :locked_by,   String
        property :failed_at,   Time
        property :last_error,  String
                
        def self.db_time_now
          Time.now.utc
        end
                
        def self.find_available(worker_name, limit = 5, max_run_time = Worker.max_run_time)
          # not yet running  
          running = all(:run_at.lte => db_time_now) 
          
          # lockable 
          lockable = (
            # not locked or past the max time
            ( all(:locked_at => nil ) | all(:locked_at.lt => db_time_now - max_run_time)) |

            # OR locked by our worker
            all(:locked_by => worker_name))
            
          # plus some other boring junk 
          (running & lockable).all( :limit => limit, :failed_at => nil, :order => [:priority.asc, :run_at.asc] )
        end
        
        # When a worker is exiting, make sure we don't have any locked jobs.
        def self.clear_locks!(worker_name)
          all(:locked_by => worker_name).update(:locked_at => nil, :locked_by => nil)
        end
        
        # Lock this job for this worker.
        # Returns true if we have the lock, false otherwise.
        def lock_exclusively!(max_run_time, worker = worker_name)
          now = self.class.db_time_now
          overtime = now - max_run_time
          
          # FIXME - this is a bit gross
          # DM doesn't give us the number of rows affected by a collection update
          # so we have to circumvent some niceness in DM::Collection here
          collection = locked_by != worker ?
            (self.class.all(:id => id, :run_at.lte => now) & ( self.class.all(:locked_at => nil) | self.class.all(:locked_at.lt => overtime) ) ) :
            self.class.all(:id => id, :locked_by => worker)
          
          attributes = collection.model.new(:locked_at => now, :locked_by => worker).dirty_attributes
          affected_rows = self.repository.update(attributes, collection)
            
          if affected_rows == 1
            self.locked_at = now
            self.locked_by = worker
            return true
          else
            return false
          end
        end
        
        # FIMXE - shouldn't the spec call load_for_delayed_job?
        def self.find id
          get id
        end
        
        # I guess Mongo and AR both have this function
        def update_attributes(attributes)
          self.update attributes
          self.save
        end
      end
      
      class JobObserver
        include ::DataMapper::Observer

        observe Job

        before :save do
          self.run_at ||= self.class.db_time_now
        end  
      end
    end
  end
end
