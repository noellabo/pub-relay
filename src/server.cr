require "./pub_relay"

handlers = [] of HTTP::Handler
handlers << HTTP::LogHandler.new if ENV["RELAY_DEBUG"]?
handlers << PubRelay.new

server = HTTP::Server.new(handlers)
bind_ip = server.bind_tcp(
  host: ENV["RELAY_HOST"]? || "localhost",
  port: (ENV["RELAY_PORT"]? || 8085).to_i,
  reuse_port: !!ENV["RELAY_REUSEPORT"]?
)

puts "Listening on #{bind_ip}"
server.listen
