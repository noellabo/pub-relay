require "dotenv"
Dotenv.load

require "./pub_relay"
require "sidekiq/cli"

cli = Sidekiq::CLI.new
server = cli.create
cli.run(server)
