require "http"
require "json"
require "openssl_ext"

class PubRelay
  VERSION = "0.1.0"

  include HTTP::Handler

  def initialize(@host : String, private_key_path : String)
    @private_key = OpenSSL::RSA.new(File.read(private_key_path))
  end

  def call(context : HTTP::Server::Context)
    case {context.request.method, context.request.path}
    when {"GET", "/.well-known/webfinger"}
      serve_webfinger(context)
    when {"GET", "/actor"}
      serve_actor(context)
      # when {"POST", "/inbox"}
      #   handle_inbox(context)
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
        publicKeyPem: @private_key.public_key.to_pem,
      },
    }.to_json(ctx.response)
  end

  def account_uri
    "acct:relay@#{@host}"
  end

  def route_url(path)
    "https://#{@host}#{path}"
  end

  private def error(context, status_code, message)
    context.response.status_code = status_code
    context.response.puts message
  end
end
