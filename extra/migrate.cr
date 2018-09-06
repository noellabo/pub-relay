require "redis"

old_redis = Redis.new(url: ENV["OLD_REDIS_URL"])
new_redis = Redis.new(url: ENV["NEW_REDIS_URL"])

old_redis.keys("subscription:*").each do |old_key|
  inbox_url = old_redis.hget(old_key, "inbox_url").not_nil!

  new_key = "relay:#{old_key}"
  new_redis.hmset(new_key, {
    inbox_url:       inbox_url,
    follow_id:       "",
    follow_actor_id: "",
    state:           "Subscribed",
  })
end
