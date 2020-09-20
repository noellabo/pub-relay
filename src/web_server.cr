class HTTP::Server::Context
  property relay_request_domain : String?
end

class PubRelay::WebServer
  include HTTP::Handler
  include Earl::Agent
  include Earl::Logger

  class ClientError < Exception
    getter status_code : Int32
    getter error_code : String

    def initialize(@status_code, @error_code, user_portion)
      super("#{@error_code} #{user_portion}")
    end
  end

  def initialize(
    @domain : String,
    @private_key : OpenSSL::PKey::RSA,
    @subscription_manager : SubscriptionManager,
    @bindhost : String,
    @port : Int32,
    @stats : Stats,
    @redis : Redis::PooledClient
  )
  end

  @server : HTTP::Server?

  def call
    @server = server = HTTP::Server.new(self)

    bind_ip = server.bind_tcp(@bindhost, @port)
    log.info("Listening on #{bind_ip}")

    server.listen
  end

  def terminate
    @server.try(&.close)
  end

  def reset
    @server = nil
  end

  def call(context : HTTP::Server::Context)
    start_time = Time.monotonic
    exception = nil
    begin
      case {context.request.method, context.request.path}
      when {"GET", "/.well-known/webfinger"}
        serve_webfinger(context)
      when {"GET", "/.well-known/nodeinfo"}
        serve_nodeinfo_wellknown(context)
      when {"GET", "/nodeinfo/2.0"}
        serve_nodeinfo_2_0(context)
      when {"GET", "/actor/outbox"}
        serve_actor_outbox(context)
      when {"GET", "/actor/followers"}
        serve_actor_followers(context)
      when {"GET", "/actor/following"}
        serve_actor_following(context)
      when {"GET", "/actor"}
        serve_actor(context)
      when {"GET", "/stats"}
        serve_stats(context)
      when {"POST", "/inbox"}
        handle_inbox(context)
      else
        call_next(context)
      end
    rescue exception : ClientError
      begin
        context.response.status_code = exception.status_code
        context.response.print exception.message
      rescue ignored
      end
    rescue exception
      begin
        context.response.status_code = 500
        context.response.print "Internal Server Error!"
      rescue ignored
      end
    end

    time = Time.monotonic - start_time
    log_message = "#{context.request.method} #{context.request.resource} - #{context.response.status_code} (#{time.total_milliseconds.round(2)}ms)"

    case exception
    when ClientError
      log.warn "#{log_message} #{exception.message}"
      @stats.send Stats::HTTPResponsePayload.new(exception.error_code, context.relay_request_domain)
    when Exception
      log.error log_message
      log.error exception
      @stats.send Stats::HTTPResponsePayload.new("500", context.relay_request_domain)
    else
      log.debug log_message
      @stats.send Stats::HTTPResponsePayload.new(context.response.status_code.to_s, context.relay_request_domain)
    end
  end

  private def serve_webfinger(ctx)
    account_uri = "acct:relay@#{@domain}"

    resource = ctx.request.query_params["resource"]?
    error(400, "Resource query parameter not present") unless resource
    error(404, "Resource not found") unless resource == account_uri

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

  private def serve_nodeinfo_wellknown(ctx)
    ctx.response.content_type = "application/json"
    {
      links:   {
        {
          rel:  "http://nodeinfo.diaspora.software/ns/schema/2.0",
          href: route_url("/nodeinfo/2.0"),
        },
      },
    }.to_json(ctx.response)
  end

  private def serve_nodeinfo_2_0(ctx)
    ctx.response.content_type = "application/json; profile=http://nodeinfo.diaspora.software/ns/schema/2.0"
    {
      openRegistrations: true,
      protocols:         ["activitypub"],
      services:          {
        inbound:  [] of String,
        outbound: [] of String,
      },
      software: {
        name:    "pub-relay",
        version: "#{PubRelay::VERSION}",
      },
      usage: {
        localPosts: 0,
        users:      {
          total: 1,
        },
      },
      version: "2.0",
      metadata: {
        peers: @subscription_manager.peers
      }
    }.to_json(ctx.response)
  end

  private def serve_actor(ctx)
    ctx.response.content_type = "application/activity+json"
    {
      "@context": {"https://www.w3.org/ns/activitystreams", "https://w3id.org/security/v1"},

      id:                route_url("/actor"),
      type:              "Group",
      preferredUsername: "relay",
      inbox:             route_url("/inbox"),
      outbox:            route_url("/actor/outbox"),
      followers:         route_url("/actor/followers"),
      following:         route_url("/actor/following"),

      publicKey: {
        id:           route_url("/actor#main-key"),
        owner:        route_url("/actor"),
        publicKeyPem: @private_key.public_key.to_pem,
      },
    }.to_json(ctx.response)
  end

  private def serve_actor_followers(ctx)
    if ctx.request.query_params.has_key?("page")
      ctx.response.content_type = "application/json"
      {
        "@context"     => "https://www.w3.org/ns/activitystreams",
        "id"           => route_url("/actor/followers"),
        "type"         => "OrderedCollectionPage",
        "totalItems"   => 0,
        "partOf"       => route_url("/actor/followers"),
        "orderedItems" => [] of String,
      }.to_json(ctx.response)
    else
      ctx.response.content_type = "application/json"
      {
        "@context"     => "https://www.w3.org/ns/activitystreams",
        "id"           => route_url("/actor/followers"),
        "type"         => "OrderedCollection",
        "totalItems"   => 0,
        "first"        => route_url("/actor/followers?page=1"),
      }.to_json(ctx.response)
    end
  end

  private def serve_actor_following(ctx)
    if ctx.request.query_params.has_key?("page")
      ctx.response.content_type = "application/json"
      {
        "@context"     => "https://www.w3.org/ns/activitystreams",
        "id"           => route_url("/actor/following"),
        "type"         => "OrderedCollectionPage",
        "totalItems"   => 0,
        "partOf"       => route_url("/actor/following"),
        "orderedItems" => [] of String,
      }.to_json(ctx.response)
    else
      ctx.response.content_type = "application/json"
      {
        "@context"     => "https://www.w3.org/ns/activitystreams",
        "id"           => route_url("/actor/following"),
        "type"         => "OrderedCollection",
        "totalItems"   => 0,
        "first"        => route_url("/actor/following?page=1"),
      }.to_json(ctx.response)
    end
  end

  private def serve_actor_outbox(ctx)
    if ctx.request.query_params.has_key?("page")
      ctx.response.content_type = "application/json"
      {
        "@context"     => "https://www.w3.org/ns/activitystreams",
        "id"           => route_url("/actor/outbox"),
        "type"         => "OrderedCollectionPage",
        "totalItems"   => 0,
        "partOf"       => route_url("/actor/outbox"),
        "orderedItems" => [] of String,
      }.to_json(ctx.response)
    else
      ctx.response.content_type = "application/json"
      {
        "@context"     => "https://www.w3.org/ns/activitystreams",
        "id"           => route_url("/actor/outbox"),
        "type"         => "OrderedCollection",
        "totalItems"   => 0,
        "first"        => route_url("/actor/outbox?page=1"),
      }.to_json(ctx.response)
    end
  end

  private def serve_stats(ctx)
    ctx.response.content_type = "application/json"
    @stats.to_json(ctx.response)
  end

  private def handle_inbox(context)
    InboxHandler.new(context, @domain, @subscription_manager, @redis).handle
  end

  private def route_url(path)
    "https://#{@domain}#{path}"
  end

  private def error(status_code, error_code, user_message = "")
    raise WebServer::ClientError.new(status_code, error_code, user_message)
  end
end

require "./web_server/inbox_handler"
