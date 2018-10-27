require "spec"
require "webmock"

require "../src/pub_relay"

Earl.application.spawn
Earl::Logger.level = Earl::Logger::Severity::ERROR
Earl::Logger.level = Earl::Logger::Severity::DEBUG if ENV["RELAY_DEBUG"]?

SPEC_REDIS = Redis::PooledClient.new(url: ENV["REDIS_URL"]? || "redis://localhost")
SPEC_PKEY  = OpenSSL::RSA.new(File.read(File.join(__DIR__, "test_actor.pem")))

Spec.before_each { SPEC_REDIS.flushdb }
Spec.before_each { WebMock.reset }

class ErrorAgent
  include Earl::Agent

  getter exception : Exception?

  def call
    raise "Cannot start ErrorAgent"
  end

  def trap(agent, exception)
    raise "Two exceptions logged!" unless @exception.nil?
    @exception = exception
  end
end

def request(method, resource, headers = nil, body = nil)
  request = HTTP::Request.new(method, resource, headers, body)

  response = HTTP::Server::Response.new(IO::Memory.new)
  response_body = IO::Memory.new
  response.output = response_body

  context = HTTP::Server::Context.new(request, response)

  stats = PubRelay::Stats.new
  subscription_manager = PubRelay::SubscriptionManager.new(
    relay_domain: "example.com",
    private_key: SPEC_PKEY,
    redis: SPEC_REDIS,
    stats: stats
  )

  PubRelay::WebServer.new(
    domain: "example.com",
    private_key: SPEC_PKEY,
    subscription_manager: subscription_manager,
    bindhost: "localhost",
    port: 0,
    stats: stats
  ).call(context)

  {response.status_code, response_body.to_s, response.headers}
end
