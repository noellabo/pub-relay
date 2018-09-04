require "http"
require "json"
require "openssl_ext"
require "redis"
require "earl"

class PubRelay < Earl::Supervisor
  VERSION = "0.1.0"

  def initialize(
    domain : String,
    private_key : OpenSSL::RSA,
    redis : Redis::PooledClient,
    bindhost : String,
    port : Int32
  )
    super()

    stats = Stats.new
    monitor(stats)

    web_server = WebServer.new(domain, private_key, redis, bindhost, port, stats)
    monitor(web_server)
  end
end

require "./stats"
require "./web_server"
