require "dotenv"
Dotenv.load

require "./pub_relay"

raise "REDIS_URL must start with redis:// or rediss://" unless ENV["REDIS_URL"].starts_with? %r(redis(s?)://)

domain = ENV["RELAY_DOMAIN"]
redis = Redis::PooledClient.new(url: ENV["REDIS_URL"])
bindhost = ENV["RELAY_HOST"]? || "localhost"
port = (ENV["RELAY_PORT"]? || 8085).to_i

private_key_path = ENV["RELAY_PKEY_PATH"]
private_key = OpenSSL::PKey::RSA.new(File.read(private_key_path))

Earl::Logger.level = Earl::Logger::Severity::DEBUG if ENV["RELAY_DEBUG"]?

relay = PubRelay.new(domain, private_key, redis, bindhost, port)
Earl.application.monitor(relay)
Earl.application.start
