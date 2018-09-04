require "../activity"
require "./http_signature"

class PubRelay::WebServer::InboxHandler
  def initialize(
    @context : HTTP::Server::Context,
    @domain : String,
    @redis : Redis::PooledClient
  )
  end

  def handle
    http_signature = HTTPSignature.new(@context)
    request_body, actor_from_signature = http_signature.verify_signature

    # TODO: handle blocks

    begin
      activity = Activity.from_json(request_body)
    rescue ex : JSON::Error
      error(400, "Invalid activity JSON\n#{ex.inspect_with_backtrace}")
    end

    case activity
    when .follow?
      handle_follow(actor_from_signature, activity)
    when .unfollow?
      handle_unfollow(actor_from_signature, activity)
    when .valid_for_rebroadcast?
      handle_forward(actor_from_signature, request_body)
    end

    response.status_code = 202
    response.puts "OK"
  end

  def handle_follow(actor, activity)
    unless activity.object_is_public_collection?
      error(400, "Follow only allowed for #{Activity::PUBLIC_COLLECTION}")
    end

    accept_activity = {
      "@context": {"https://www.w3.org/ns/activitystreams"},

      id:     route_url("/actor#accepts/follows/#{actor.domain}"),
      type:   "Accept",
      actor:  route_url("/actor"),
      object: {
        id:     activity.id,
        type:   "Follow",
        actor:  actor.id,
        object: route_url("/actor"),
      },
    }

    @redis.hset("subscription:#{actor.domain}", "inbox_url", actor.inbox_url)

    # DeliverWorker.async.perform(actor.domain, accept_activity.to_json)
  end

  def handle_unfollow(actor, activity)
    @redis.del("subscription:#{actor.domain}")
  end

  def handle_forward(actor, request_body)
    # TODO: cache the subscriptions
    bulk_args = @redis.keys("subscription:*").compact_map do |key|
      key = key.as(String)
      domain = key.lchop("subscription:")
      raise "redis bug" if domain == key

      if domain == actor.domain
        nil
      else
        {domain, request_body}
      end
    end

    # DeliverWorker.async.perform_bulk(bulk_args)
  end

  private def error(status_code, message)
    raise WebServer::ClientError.new(status_code, message)
  end

  private def route_url(path)
    "https://#{@domain}#{path}"
  end

  private def request
    @context.request
  end

  private def response
    @context.response
  end
end
