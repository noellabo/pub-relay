require "./pub_relay"
require "sidekiq/cli"

ENV["REDIS_PROVIDER"] = "REDIS_URL"

cli = Sidekiq::CLI.new
server = cli.create
cli.run(server)
