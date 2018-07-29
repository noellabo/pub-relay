require "http"
require "json"
require "openssl_ext"
require "redis"
require "sidekiq"

require "./inbox_handler"

class PubRelay
  VERSION = "0.1.0"

  include HTTP::Handler

  class_getter redis = begin
    uri = URI.parse(ENV["REDIS_URL"]? || "redis://localhost")
    host = uri.host.to_s
    port = uri.port || 6379
    password = uri.password
    if (path = uri.path) && path.size > 1
      db = path[1..-1].to_i
    else
      db = 0
    end

    cfg = Sidekiq::RedisConfig.new(host, port, password: password, db: db)
    Sidekiq::Client.default_context = Sidekiq::Client::Context.new(cfg)

    Redis::PooledClient.new(host, port, password: password, database: db)
  end

  class_property(private_key) do
    private_key_path = ENV["RELAY_PKEY_PATH"]? || File.join(Dir.current, "actor.pem")
    OpenSSL::RSA.new(File.read(private_key_path))
  end

  class_property(host) { ENV["RELAY_DOMAIN"] }

  def call(context : HTTP::Server::Context)
    case {context.request.method, context.request.path}
    when {"GET", "/.well-known/webfinger"}
      serve_webfinger(context)
    when {"GET", "/actor"}
      serve_actor(context)
    when {"POST", "/inbox"}
      handle_inbox(context)
    end
  end

  private def serve_webfinger(ctx)
    resource = ctx.request.query_params["resource"]?
    return error(ctx, 400, "Resource query parameter not present") unless resource
    return error(ctx, 404, "Resource not found") unless resource == account_uri

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
