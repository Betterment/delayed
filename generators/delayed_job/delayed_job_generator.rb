class DelayedJobGenerator < Rails::Generator::Base
  
  def manifest
    record do |m|
      m.template 'script', 'script/delayed_job', :chmod => 0755
    end
  end
  
end
