require "http"
require "json"

class PubRelay
  VERSION = "0.1.0"

  include HTTP::Handler

  def initialize(@host : String)
    @account_uri = "acct:relay@#{@host}"
  end

  def call(context : HTTP::Server::Context)
    case {context.request.method, context.request.path}
    when {"GET", "/.well-known/webfinger"}
      serve_webfinger(context)
      # when {"GET", "/actor"}
      #   serve_actor(context)
      # when {"POST", "/inbox"}
      #   handle_inbox(context)
    end
  end

  private def serve_webfinger(ctx)
    resource = ctx.request.query_params["resource"]?
    return error(ctx, 400, "Resource query parameter not present") unless resource
    return error(ctx, 404, "Resource not found") unless resource == @account_uri

    {
      subject: @account_uri,
      links:   {
        {
          rel:  "self",
          type: "application/activity+json",
          href: "https://#{@host}/actor",
        },
      },
    }.to_json(ctx.response)
  end

  private def error(context, status_code, message)
    context.response.status_code = status_code
    context.response.puts message
  end
end
