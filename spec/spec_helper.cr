require "spec"
require "webmock"

require "../src/pub_relay"

def request(method, resource, headers = nil, body = nil)
  request = HTTP::Request.new(method, resource, headers, body)

  response = HTTP::Server::Response.new(IO::Memory.new)
  response_body = IO::Memory.new
  response.output = response_body

  context = HTTP::Server::Context.new(request, response)

  PubRelay.new("example.com", File.join(__DIR__, "test_actor.pem")).call(context)

  {response.status_code, response_body.to_s, response.headers}
end
