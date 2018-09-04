require "spec"
require "webmock"

require "../src/pub_relay"

Earl.application.spawn
Earl::Logger.level = Earl::Logger::Severity::ERROR
Earl::Logger.level = Earl::Logger::Severity::DEBUG if ENV["RELAY_DEBUG"]?

def request(method, resource, headers = nil, body = nil)
  request = HTTP::Request.new(method, resource, headers, body)

  response = HTTP::Server::Response.new(IO::Memory.new)
  response_body = IO::Memory.new
  response.output = response_body

  context = HTTP::Server::Context.new(request, response)

  private_key = OpenSSL::RSA.new(File.read(File.join(__DIR__, "test_actor.pem")))
  PubRelay::WebServer.new(
    domain: "example.com",
    private_key: private_key,
    redis: Redis::PooledClient.new(url: ENV["REDIS_URL"]? || "redis://localhost"),
    bindhost: "localhost",
    port: 0
  ).call(context)

  {response.status_code, response_body.to_s, response.headers}
end
