require "./pub_relay"

handlers = [] of HTTP::Handler
handlers << HTTP::LogHandler.new if ENV["RELAY_DEBUG"]?
handlers << PubRelay.new(
  host: ENV["RELAY_DOMAIN"],
  private_key_path: ENV["RELAY_PKEY_PATH"]? || File.join(Dir.current, "actor.pem")
)

server = HTTP::Server.new(handlers)
bind_ip = server.bind_tcp(
  host: ENV["RELAY_HOST"]? || "localhost",
  port: (ENV["RELAY_PORT"]? || 8085).to_i,
  reuse_port: !!ENV["RELAY_REUSEPORT"]?
)

puts "Listening on #{bind_ip}"
server.listen
