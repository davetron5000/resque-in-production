# config/initializers/resque.rb
require 'resque_scheduler'
require 'resque-retry'
require 'resque_scheduler/server'
require 'resque-retry/server'

configuration = {
  host: ENV['RESQUE_REDIS_HOST'],
  port: ENV['RESQUE_REDIS_PORT'],
}
Resque.redis = Redis.new(configuration)

require 'resque/failure/redis'
Resque::Failure::MultipleWithRetrySuppression.classes = [Resque::Failure::Redis]
Resque::Failure.backend = Resque::Failure::MultipleWithRetrySuppression

