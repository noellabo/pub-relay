require "../activity"
require "./http_signature"

class PubRelay::WebServer::InboxHandler
  def initialize(
    @context : HTTP::Server::Context,
    @domain : String,
    @subscription_manager : SubscriptionManager
  )
  end

  def handle
    http_signature = HTTPSignature.new(@context)
    request_body, actor_from_signature = http_signature.verify_signature

    # TODO: handle blocks

    begin
      activity = Activity.from_json(request_body)
    rescue ex : JSON::Error
      error(400, "Invalid activity JSON:", "\n#{ex.inspect_with_backtrace}")
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

    inbox_url = URI.parse(actor.inbox_url) rescue nil
    error(400, "Inbox URL was not a valid URL") unless inbox_url

    @subscription_manager.send(
      SubscriptionManager::Subscription.new(
        domain: actor.domain,
        inbox_url: inbox_url,
        follow_id: activity.id,
        follow_actor_id: actor.id
      )
    )
  end

  def handle_unfollow(actor, activity)
    @subscription_manager.send(
      SubscriptionManager::Unsubscription.new(actor.domain)
    )
  end

  def handle_forward(actor, request_body)
    @subscription_manager.deliver(request_body, source_domain: actor.domain)
  end

  private def error(status_code, error_code, user_message = "")
    raise WebServer::ClientError.new(status_code, error_code, user_message)
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
