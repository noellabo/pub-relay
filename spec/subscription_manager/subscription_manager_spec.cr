require "../spec_helper"

def with_subscription_manager
  subscription_manager = PubRelay::SubscriptionManager.new(
    relay_domain: "example.com",
    private_key: SPEC_PKEY,
    redis: SPEC_REDIS,
    stats: PubRelay::Stats.new
  )

  error_agent = ErrorAgent.new
  subscription_manager.spawn(link: error_agent)
  yield subscription_manager

  sleep 10.milliseconds

  raise error_agent.exception.not_nil! if subscription_manager.crashed?
  subscription_manager.running?.should be_true
  subscription_manager.stop
end

private alias SubMan = PubRelay::SubscriptionManager

describe PubRelay::SubscriptionManager do
  it "handles unsubscribing non-existant subscriptions" do
    with_subscription_manager do |manager|
      manager.send SubMan::Unsubscription.new("non-existant.com")
    end
  end

  it "recycles gracefully" do
    with_subscription_manager do |manager|
      # Send a subscription to spawn a worker
      manager.send SubMan::Subscription.new(
        domain: "example.com",
        inbox_url: URI.parse("https://example.com/inbox"),
        follow_id: "https://example.com/follow_id",
        follow_actor_id: "https://example.com/follow_actor_id"
      )

      sleep 5.milliseconds
      manager.@workers.size.should eq(1)
      manager.running?.should be_true

      # Send a bogus AcceptSent to crash the manager
      manager.send SubMan::AcceptSent.new("non-existant.com")

      sleep 5.milliseconds
      manager.crashed?.should be_true

      # Simulate the recycle -> restart cycle of a supervisor
      manager.recycle

      manager.starting?.should be_true
      manager.spawn
    end
  end
end
