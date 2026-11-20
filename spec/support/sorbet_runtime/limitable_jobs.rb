# frozen_string_literal: true

require 'sorbet-runtime'
require 'active_job'
require 'delayed'

ActiveJob::Base.logger = Logger.new(nil)

LIMITED = [] # rubocop:disable Style/MutableConstant

Delayed::Limit.singleton_class.prepend(Module.new do
  def within_limit(purpose, **)
    LIMITED << purpose
    yield
  end
end)

class ApplicationJob < ActiveJob::Base; end

class KwargsJob < ApplicationJob
  extend T::Sig

  with_limit :kwargs_job

  sig { params(id: Integer).returns(Integer) }
  def perform(id:)
    id
  end
end

class PositionalJob < ApplicationJob
  extend T::Sig

  with_limit :positional_job

  sig { params(id: Integer).returns(Integer) }
  def perform(id)
    id
  end
end

class OnMethodJob < ApplicationJob
  extend T::Sig

  with_limit :on_method_job, on: :deliver!

  sig { params(id: Integer).returns(Integer) }
  def perform(id:)
    deliver!(id: id)
  end

  sig { params(id: Integer).returns(Integer) }
  def deliver!(id:)
    id * 10
  end
end

class PlainLimitable
  extend T::Sig
  include Delayed::Limitable

  with_limit :plain_limitable, on: :do_work

  sig { params(id: Integer).returns(Integer) }
  def do_work(id:)
    id
  end
end

def check(description, expected_result, expected_limited)
  LIMITED.clear
  result = yield
  return if result == expected_result && LIMITED == expected_limited

  abort "#{description}: expected #{[expected_result, expected_limited]}, got #{[result, LIMITED]}"
end

2.times do
  check('KwargsJob.perform_now', 1, %i(kwargs_job)) { KwargsJob.perform_now(id: 1) }
  check('PositionalJob.perform_now', 2, %i(positional_job)) { PositionalJob.perform_now(2) }
  check('OnMethodJob.perform_now', 30, %i(on_method_job)) { OnMethodJob.perform_now(id: 3) }
  check('PlainLimitable#do_work', 4, %i(plain_limitable)) { PlainLimitable.new.do_work(id: 4) }
end

begin
  KwargsJob.perform_now(id: 'one')
  abort 'KwargsJob.perform_now: expected a TypeError from its sig'
rescue TypeError
  nil
end
