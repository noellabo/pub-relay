require "./pub_relay"
require "sidekiq/cli"

# Initialize sidekiq redis
PubRelay.redis

cli = Sidekiq::CLI.new
server = cli.create
cli.run(server)
