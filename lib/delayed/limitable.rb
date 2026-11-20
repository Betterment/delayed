# frozen_string_literal: true

module Delayed
  # A mixin that applies `Delayed::Limit.within_limit` around ActiveJob execution
  # (or around individual methods named via `on:`). It is automatically included
  # in ActiveJob classes, and configures the job to retry with a polynomial
  # backoff when the limit's `wait_timeout` would be exceeded:
  #
  #   class TouchesThirdPartyApiJob < ApplicationJob
  #     with_limit :third_party_api, max: 100, per: 1.minute
  #
  #     def perform
  #       # ...
  #     end
  #   end
  #
  # The 'purpose' defaults to the job's underscored class name, and the limit
  # is registered via `Delayed::Limit.register!` (unless the purpose was
  # already registered, e.g. in an initializer, in which case the `max:`/`per:`
  # config may be omitted entirely). Multiple job classes may share a purpose
  # (and its limit) as long as their configs match exactly.
  #
  # Use `on:` to wrap one or more other instance methods instead of `perform`,
  # e.g. if only a portion of the job's work is subject to the limit:
  #
  #   with_limit :third_party_api, max: 100, per: 1.minute, on: :deliver!
  #
  # A class may declare `with_limit` more than once (e.g. to apply different
  # limits to different methods), but only the first declaration defines the
  # job's retry behavior (`attempts`, `wait`, and `jitter`, with `wait_timeout`
  # acting as a floor on the computed wait). If two declarations' wait timeouts
  # differ meaningfully, declare the one with the longer `wait_timeout` first.
  #
  # Retries rely on ActiveJob's `retry_on`, so when this mixin is included in
  # a plain (non-ActiveJob) class, the named methods are still wrapped in
  # `within_limit`, but the class must define its own rescue/retry behavior
  # for `Delayed::Limit::LimitExceededError`.
  module Limitable
    extend ActiveSupport::Concern

    DEFAULT_RETRY_ATTEMPTS = if defined?(ActiveJob) && ActiveJob.gem_version >= Gem::Version.new('7.0')
      :unlimited
    else
      Float::INFINITY
    end

    DEFAULT_LIMIT_TARGET = Object.new.freeze
    private_constant :DEFAULT_LIMIT_TARGET

    class_methods do
      def with_limit(
        purpose = name.underscore.to_sym,
        on: DEFAULT_LIMIT_TARGET,
        max: nil,
        per: nil,
        wait_timeout: 5.seconds,
        retry_jitter: 0.1,
        retry_attempts: DEFAULT_RETRY_ATTEMPTS,
        retry_wait: ->(attempt) { polynomial_backoff(wait_timeout, attempt, retry_jitter) }
      )
        Delayed::Limit.register!(purpose, max: max, per: per) if max || per

        active_job = defined?(ActiveJob::Base) && self < ActiveJob::Base
        if active_job && rescue_handlers.none? { |klass, _| klass == Delayed::Limit::LimitExceededError.name }
          retry_on(Delayed::Limit::LimitExceededError, attempts: retry_attempts, wait: retry_wait)
        end

        apply_limit(purpose, wait_timeout, on, active_job: active_job)
      end

      private

      def apply_limit(purpose, wait_timeout, on, active_job:)
        default_target = on.equal?(DEFAULT_LIMIT_TARGET)
        if active_job && default_target
          around_perform do |_, perform|
            Delayed::Limit.within_limit(purpose, wait_timeout: wait_timeout, &perform)
          end
        else
          wrap_limited_methods(default_target ? :perform : on, purpose, wait_timeout)
        end
      end

      def wrap_limited_methods(on, purpose, wait_timeout)
        prepend(Module.new do
          Array(on).each do |method_name|
            define_method(method_name) do |*args, **kwargs, &block|
              Delayed::Limit.within_limit(purpose, wait_timeout: wait_timeout) do
                super(*args, **kwargs, &block)
              end
            end
          end
        end)
      end

      def polynomial_backoff(min_wait, attempt, jitter)
        [min_wait, (attempt**4)].max * (1 + rand(-jitter..jitter))
      end
    end
  end
end
