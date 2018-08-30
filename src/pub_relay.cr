require "http"
require "json"
require "openssl_ext"
require "redis"
require "sidekiq"

require "./inbox_handler"

class PubRelay
  VERSION = "0.1.0"

  include HTTP::Handler

  # Make sidekiq use REDIS_URL
  ENV["REDIS_URL"] ||= "redis://localhost:6379"
  ENV["REDIS_PROVIDER"] = "REDIS_URL"
  Sidekiq::Client.default_context = Sidekiq::Client::Context.new

  class_getter redis = Redis::PooledClient.new(url: ENV["REDIS_URL"])

  class_property(private_key) do
    private_key_path = ENV["RELAY_PKEY_PATH"]? || File.join(Dir.current, "actor.pem")
    OpenSSL::RSA.new(File.read(private_key_path))
  end

  class_property(host) { ENV["RELAY_DOMAIN"] }

  class_property logger = Logger.new(STDOUT)

  def call(context : HTTP::Server::Context)
    case {context.request.method, context.request.path}
    when {"GET", "/.well-known/webfinger"}
      serve_webfinger(context)
    when {"GET", "/actor"}
      serve_actor(context)
    when {"POST", "/inbox"}
      handle_inbox(context)
    else
      call_next(context)
    end
  end

  private def serve_webfinger(ctx)
    resource = ctx.request.query_params["resource"]?
    return error(ctx, 400, "Resource query parameter not present") unless resource
    return error(ctx, 404, "Resource not found") unless resource == account_uri

    ctx.response.content_type = "application/json"
    {
      subject: account_uri,
      links:   {
        {
          rel:  "self",
          type: "application/activity+json",
          href: route_url("/actor"),
        },
      },
    }.to_json(ctx.response)
  end

  private def serve_actor(ctx)
    ctx.response.content_type = "application/activity+json"
    {
      "@context": {"https://www.w3.org/ns/activitystreams", "https://w3id.org/security/v1"},

      id:                route_url("/actor"),
      type:              "Service",
      preferredUsername: "relay",
      inbox:             route_url("/inbox"),

      publicKey: {
        id:           route_url("/actor#main-key"),
        owner:        route_url("/actor"),
        publicKeyPem: PubRelay.private_key.public_key.to_pem,
      },
    }.to_json(ctx.response)
  end

  private def handle_inbox(context)
    InboxHandler.new(context).handle
  end

  def account_uri
    "acct:relay@#{PubRelay.host}"
  end

  def self.route_url(path)
    "https://#{host}#{path}"
  end

  def route_url(path)
    PubRelay.route_url(path)
  end

  private def error(context, status_code, message)
    context.response.status_code = status_code
    context.response.puts message
  end
end
