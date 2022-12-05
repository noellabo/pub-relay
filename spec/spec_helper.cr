require "spec"
require "webmock"

require "../src/pub_relay"

Earl.application.spawn
Earl::Logger.level = Earl::Logger::Severity::ERROR
Earl::Logger.level = Earl::Logger::Severity::DEBUG if ENV["RELAY_DEBUG"]?

SPEC_REDIS = Redis::PooledClient.new(url: ENV["REDIS_URL"]? || "redis://localhost")
SPEC_PKEY  = OpenSSL::PKey::RSA.new(File.read(File.join(__DIR__, "test_actor.pem")))

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
    redis: SPEC_REDIS,
    subscription_manager: subscription_manager,
    bindhost: "localhost",
    port: 0,
    reuse_port: true,
    stats: stats
  ).call(context)

  {response.status_code, response_body.to_s, response.headers}
end

private alias HTTPSignature = PubRelay::WebServer::HTTPSignature

module WebMock
  class_getter registry
end

private class IntegrationTest
  getter domain_keys = Hash(String, OpenSSL::PKey::RSA).new

  def initialize
    @pub_relay = PubRelay.new("relay.com", SPEC_PKEY, SPEC_REDIS, "localhost", 0)
    @pub_relay.spawn

    relay_actor = HTTPSignature::Actor.new(
      id: "https://relay.com/actor",
      public_key: HTTPSignature::Key.new(
        public_key_pem: SPEC_PKEY.public_key.to_pem,
        owner: "https://relay.com/actor"
      ),
      endpoints: nil,
      inbox: "https://relay.com/inbox"
    )

    WebMock.stub("GET", "https://relay.com/actor")
      .to_return(body: relay_actor.to_json)
  end

  def request(method, resource, headers = nil, body = nil)
    request = HTTP::Request.new(method, resource, headers, body)

    response = HTTP::Server::Response.new(IO::Memory.new)
    response_body = IO::Memory.new
    response.output = response_body

    context = HTTP::Server::Context.new(request, response)

    @pub_relay.web_server.call(context)

    {response.status_code, response_body.to_s, response.headers}
  end

  def add_domain(domain)
    domain_keys[domain] = OpenSSL::PKey::RSA.new(512)

    domain_actor = HTTPSignature::Actor.new(
      id: "https://#{domain}/actor",
      public_key: HTTPSignature::Key.new(
        public_key_pem: domain_keys[domain].public_key.to_pem,
        owner: "https://#{domain}/actor"
      ),
      endpoints: nil,
      inbox: "https://#{domain}/inbox"
    )

    WebMock.stub("GET", "https://#{domain}/actor")
      .to_return(body: domain_actor.to_json)
  end

  def signed_inbox_request(*, body : String, from source_domain : String, headers = HTTP::Headers.new)
    body_hash = OpenSSL::Digest.new("sha256")
    body_hash.update(body)
    body_hash = Base64.strict_encode(body_hash.final)

    headers["Host"] = "relay.com"
    headers["Date"] = HTTP.format_time(Time.utc)
    headers["Digest"] = "SHA-256=#{body_hash}"

    signed_headers = "(request-target) host date digest"
    signed_string = <<-END
      (request-target): post /inbox
      host: #{headers["Host"]}
      date: #{headers["Date"]}
      digest: #{headers["Digest"]}
      END

    signature = domain_keys[source_domain].sign(OpenSSL::Digest.new("sha256"), signed_string)

    headers["Signature"] = %(keyId="https://#{source_domain}/actor",headers="#{signed_headers}",signature="#{Base64.strict_encode(signature)}")

    request("POST", "/inbox", headers, body)
  end

  def signed_inbox_request(activity, *, from source_domain : String, headers = HTTP::Headers.new)
    signed_inbox_request(body: activity.to_json, from: source_domain, headers: headers)
  end

  def subscribe_domain(domain)
    add_domain(domain) unless domain_keys[domain]?

    activity = PubRelay::Activity.new(
      id: "https://#{domain}/follows/1",
      types: ["Follow"],
      published: Time.utc,
      object: PubRelay::Activity::PUBLIC_COLLECTION
    )

    # Collect initial follow Accept
    accept_channel = Channel(Nil).new
    stub = WebMock.stub("POST", "https://#{domain}/inbox")
      .to_return do |request|
        activity = PubRelay::Activity.from_json(request.body.not_nil!)
        activity.types.should contain("Accept")
        activity.object_id.should eq("https://#{domain}/follows/1")

        accept_channel.send nil

        HTTP::Client::Response.new(202)
      end

    signed_inbox_request(from: domain, body: activity.to_json)

    accept_channel.receive

    WebMock.registry.@stubs.delete(stub)

    sleep 10.milliseconds
  rescue
    raise "Accept not sent for subscribe to #{domain}"
  end

  def stop
    sleep 10.milliseconds

    @pub_relay.stop

    # Wait up to 500ms to stop
    500.times do
      sleep 1.milliseconds
      break if @pub_relay.stopped?
    end

    @pub_relay.stopped?.should be_true
  end
end

def integration_test
  integration_test = IntegrationTest.new
  with integration_test yield
  integration_test.stop
end
