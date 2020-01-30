require "http"
require "json"
require "openssl_ext"
require "redis"
require "earl"

class PubRelay < Earl::Supervisor
  VERSION = "0.1.0"

  getter stats : Stats
  getter subscription_manager : SubscriptionManager
  getter web_server : WebServer

  def initialize(
    domain : String,
    private_key : OpenSSL::PKey::RSA,
    redis : Redis::PooledClient,
    bindhost : String,
    port : Int32
  )
    super()

    @stats = Stats.new
    @subscription_manager = SubscriptionManager.new(domain, private_key, redis, stats)
    @web_server = WebServer.new(domain, private_key, subscription_manager, bindhost, port, stats)

    monitor(@stats)
    monitor(@subscription_manager)
    monitor(@web_server)
  end
end

require "./stats"
require "./subscription_manager"
require "./web_server"
