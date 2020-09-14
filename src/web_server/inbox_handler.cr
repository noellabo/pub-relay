require "../activity"
require "./http_signature"
require "uuid"
require "uuid/json"

class PubRelay::WebServer::InboxHandler
  def initialize(
    @context : HTTP::Server::Context,
    @domain : String,
    @subscription_manager : SubscriptionManager,
    @redis : Redis::PooledClient,
  )
  end

  def handle
    http_signature = HTTPSignature.new(@context, @redis)
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
    when .unfollow?, .reject?
      handle_unfollow(actor_from_signature, activity)
    when .accept?
      handle_accept(actor_from_signature, activity)
    when .older_published?
      error(200, "Skip old activity:", "\n#{activity.id}")
    when .check_duplicate?(@redis)
      error(200, "Skip the activity id that the server already knows:", "\n#{activity.id}")
    when .valid_for_rebroadcast?
      handle_forward(actor_from_signature, request_body)
    when .valid_for_relay?
      handle_relay(actor_from_signature, activity)
    end

    response.status_code = 202
    response.puts "OK"
  end

  def handle_follow(actor, activity)
    inbox_url = URI.parse(actor.inbox_url) rescue nil
    error(400, "Inbox URL was not a valid URL") unless inbox_url

    if actor.pleroma_relay?
      @subscription_manager.send(
        SubscriptionManager::FollowSent.new(
          domain: actor.domain,
          inbox_url: inbox_url,
          following_id: route_url("/#{UUID.random}"),
          following_actor_id: actor.id
        )
      )
    elsif activity.object_id != Activity::PUBLIC_COLLECTION
      error(400, "Follow only allowed for #{Activity::PUBLIC_COLLECTION}")
    end

    @subscription_manager.send(
      SubscriptionManager::Subscription.new(
        domain: actor.domain,
        inbox_url: inbox_url,
        follow_id: activity.id,
        follow_actor_id: actor.id
      )
    )
  end

  def handle_accept(actor, activity)
    @subscription_manager.send(
      SubscriptionManager::AcceptReceive.new(actor.domain)
    )
  end

  def handle_unfollow(actor, activity)
    @subscription_manager.send(
      SubscriptionManager::Unsubscription.new(actor.domain)
    )
  end

  def handle_forward(actor, request_body)
    @subscription_manager.send(
      SubscriptionManager::Deliver.new(request_body, source_domain: actor.domain)
    )
  end

  def handle_relay(actor, activity)
    @subscription_manager.send(
      SubscriptionManager::Announce.new(
        object: activity.object_id.not_nil!.to_s,
        source_domain: actor.domain
      )
    )
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
