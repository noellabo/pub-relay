class PubRelay::SubscriptionManager
  record Subscription,
    domain : String,
    inbox_url : URI,
    follow_id : String,
    follow_actor_id : String

  record AcceptSent,
    domain : String

  record Unsubscription,
    domain : String

  include Earl::Artist(Subscription | AcceptSent | Unsubscription)

  enum State
    Pending
    Subscribed
    Failed
    Unsubscribed

    def transition?(new_state)
      case self
      when Pending
        new_state.subscribed?
      when Subscribed
        new_state.unsubscribed? || new_state.failed?
      when Failed
        new_state.subscribed? || new_state.unsubscribed?
      when Unsubscribed
        false
      end
    end
  end

  def initialize(
    @relay_domain : String,
    @private_key : OpenSSL::RSA,
    @redis : Redis::PooledClient,
    @stats : Stats
  )
    @workers = Set(DeliverWorker).new
    @subscribed_workers = Set(DeliverWorker).new

    load_subscriptions
  end

  private def load_subscriptions
    @redis.keys(key_for("*")).each do |key|
      key = key.as(String)

      domain = key.lchop(key_for(""))
      raise "BUG" if domain == key

      inbox_url = @redis.hget(key, "inbox_url").not_nil!
      inbox_url = URI.parse inbox_url
      state = get_state(domain)

      deliver_worker = DeliverWorker.new(
        domain, inbox_url, @relay_domain, @private_key, @stats, self
      )

      @workers << deliver_worker
      @subscribed_workers << deliver_worker if state.subscribed?
    end

    log.info "Found #{@workers.size} subscriptions, #{@subscribed_workers.size} of which are subscribed"
  end

  def call
    @workers.each do |worker|
      supervise worker
    end

    while message = receive?
      call(message)
    end
  end

  def call(subscription : Subscription)
    log.info "Received subscription for #{subscription.domain}"

    deliver_worker = DeliverWorker.new(
      subscription.domain, subscription.inbox_url, @relay_domain, @private_key, @stats, self
    )

    @redis.hmset(key_for(subscription.domain), {
      inbox_url:       subscription.inbox_url,
      follow_id:       subscription.follow_id,
      follow_actor_id: subscription.follow_actor_id,
      state:           State::Pending.to_s,
    })

    supervise deliver_worker

    accept_activity = {
      "@context": "https://www.w3.org/ns/activitystreams",

      id:     route_url("/actor#accepts/follows/#{subscription.domain}"),
      type:   "Accept",
      actor:  route_url("/actor"),
      object: {
        id:     subscription.follow_id,
        type:   "Follow",
        actor:  subscription.follow_actor_id,
        object: route_url("/actor"),
      },
    }

    counter = new_counter
    delivery = DeliverWorker::Delivery.new(
      accept_activity.to_json, @relay_domain, counter, accept: true
    )
    deliver_worker.send delivery
  end

  def call(accept : AcceptSent)
    state = get_state(accept.domain)
    raise "#{accept.domain}'s state as #{state}, not pending" unless state.pending?
    transition_state(accept.domain, :subscribed)

    worker = @workers.find { |worker| worker.domain == accept.domain }
    raise "Worker not found" unless worker
    @subscribed_workers << worker
  end

  def call(unsubscribe : Unsubscription)
    deliver_worker = @workers.find { |worker| worker.domain == unsubscribe.domain }
    raise "Worker not found for unsubscribe" unless deliver_worker
    @subscribed_workers.delete(deliver_worker)

    transition_state(unsubscribe.domain, :unsubscribed)

    @workers.delete(deliver_worker)
    deliver_worker.stop

    @redis.del(key_for(unsubscribe.domain))
  end

  def deliver(message : String, source_domain : String)
    counter = new_counter
    delivery = DeliverWorker::Delivery.new(message, source_domain, counter, accept: false)

    select_actions = @subscribed_workers.map(&.mailbox.send_select_action(delivery))

    spawn do
      until select_actions.empty?
        index, _ = Channel.select(select_actions)
        select_actions.delete_at(index)
      end
    end
  end

  @deliver_counter = 0

  private def new_counter : Int32
    counter = @deliver_counter += 1
    @stats.send Stats::DeliveryCounterPayload.new(counter)
    counter
  end

  private def transition_state(domain, new_state : State)
    state = get_state(domain)

    raise "Invalid transition for #{domain} (#{state} -> #{new_state})" unless state.transition? new_state
    log.info "Transitioning #{domain} (#{state} -> #{new_state})"

    @redis.hset(key_for(domain), "state", new_state.to_s)
  end

  private def get_state(domain) : State
    state = @redis.hget(key_for(domain), "state")
    raise "BUG: subscription doesn't exist" unless state
    State.parse(state)
  end

  private def key_for(domain)
    "relay:subscription:#{domain}"
  end

  private def supervise(deliver_worker)
    @workers << deliver_worker

    spawn do
      log.error "Supervision started when subscription manager not running!" unless self.running?
      while self.running? && deliver_worker.starting?
        deliver_worker.start(link: self)
      end
    end
  end

  @failure_counts = Hash(String, Int32).new(0)

  def trap(agent, exception)
    return log.error("Trapped agent was not a DeliverWorker!") unless agent.is_a? DeliverWorker

    # This is a worker unsubscribing
    return if agent.stopping? && !@workers.includes?(agent)

    if exception
      Earl::Logger.error(agent, exception) if exception
      log.error { "#{agent.class.name} crashed (#{exception.class.name})" }
    else
      log.error { "#{agent.class.name} exited early" } if self.running?
    end

    @failure_counts[agent.domain] += 1
    agent.recycle if self.running?
  end

  private def route_url(path)
    "https://#{@relay_domain}#{path}"
  end

  def terminate
    @workers.each do |agent|
      agent.stop if agent.running?
    end
  end

  def reset
    old_workers = @workers

    @workers = Set(DeliverWorker).new
    @subscribed_workers = Set(DeliverWorker).new
    load_subscriptions

    old_workers.each do |worker|
      worker.stop if worker.running?
    end
  end
end

require "./deliver_worker"
