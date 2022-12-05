require "dotenv"
Dotenv.load?

require "./pub_relay"

raise "RELAY_DOMAIN must be specified." unless ENV.has_key?("RELAY_DOMAIN")
raise "REDIS_URL must start with redis:// or rediss://" unless ENV.has_key?("REDIS_URL") && ENV["REDIS_URL"].starts_with?(%r(redis(s?)://))

domain = ENV["RELAY_DOMAIN"]
redis = Redis::PooledClient.new(
  url: ENV["REDIS_URL"]? || "redis://localhost:6379/1",
  pool_size: (ENV["REDIS_POOL_SIZE"]? || 5).to_i
)
bindhost = ENV["RELAY_HOST"]? || "localhost"
port = (ENV["RELAY_PORT"]? || 8085).to_i
reuse_port = !!(ENV["RELAY_REUSEPORT"]? || false)

private_key_path = ENV["RELAY_PKEY_PATH"]? || ".private/actor.pem"

if File.exists?(private_key_path)
  private_key = OpenSSL::PKey::RSA.new(File.read(private_key_path))
else
  private_key = OpenSSL::PKey::RSA.new(2048)
  Dir.mkdir_p(File.dirname(private_key_path), 0o700)
  File.write(private_key_path, private_key.to_pem)
  File.chmod(private_key_path, 0o600)
end

STDOUT.sync = true if ENV["RELAY_DEBUG"]?
Earl::Logger.level = Earl::Logger::Severity::DEBUG if ENV["RELAY_DEBUG"]?

relay = PubRelay.new(domain, private_key, redis, bindhost, port, reuse_port)
Earl.application.monitor(relay)
Earl.application.start
