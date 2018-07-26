require "./activity"
require "./deliver_worker"

class InboxHandler
  class Error < Exception
  end

  def initialize(@context : HTTP::Server::Context)
  end

  def handle
    request_body, actor_from_signature = verify_signature

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
  rescue ignored : InboxHandler::Error
    # error output was already set
  end

  def handle_follow(actor, activity)
    unless activity.object_is_public_collection?
      error(400, "Follow only allowed for #{Activity::PUBLIC_COLLECTION}")
    end

    PubRelay.redis.hset("subscription:#{actor.domain}", "inbox_url", actor.inbox_url)
  end

  def handle_unfollow(actor, activity)
    PubRelay.redis.del("subscription:#{actor.domain}")
  end

  def handle_forward(actor, request_body)
    # TODO: cache the subscriptions
    bulk_args = PubRelay.redis.keys("subscription:*").compact_map do |key|
      key = key.as(String)
      domain = key.lchop("subscription:")
      raise "redis bug" if domain == key

      if domain == actor.domain
        nil
      else
        {domain, request_body}
      end
    end

    DeliverWorker.async.perform_bulk(bulk_args)
  end

  # Verify HTTP signatures according to https://tools.ietf.org/html/draft-cavage-http-signatures-06.
  # In this specific implementation keyId is the URL to either an ActivityPub actor or
  # a [Web Payments Key](https://web-payments.org/vocabs/security#Key).
  private def verify_signature : {String, Actor}
    signature_header = request.headers["Signature"]?
    error(401, "Request not signed: no Signature header") unless signature_header

    signature_params = parse_signature(signature_header)

    key_id = signature_params["keyId"]?
    error(400, "Invalid Signature: keyId not present") unless key_id

    signature = signature_params["signature"]?
    error(400, "Invalid Signature: signature not present") unless signature

    # NOTE: `actor_from_key_id` can take time performing a HTTP request, so it should
    # complete before `build_signed_string`, which can load the request body into memory.
    actor = actor_from_key_id(key_id)

    error(400, "No request body") unless body = request.body

    body = String.build do |io|
      copy_size = IO.copy(body, io, 4_096_000)
      error(400, "Request body too large") if copy_size == 4_096_000
    end

    signed_string = build_signed_string(body, signature_params["headers"]?)

    public_key = OpenSSL::RSA.new(actor.public_key.public_key_pem, is_private: false)

    begin
      signature = Base64.decode(signature)
    rescue err : Base64::Error
      error(400, "Invalid Signature: Invalid base64 in signature value")
    end

    if public_key.verify(OpenSSL::Digest.new("SHA256"), signature, signed_string)
      {body, actor}
    else
      error(401, "Invalid Signature: cryptographic signature did not verify for #{key_id.inspect}")
    end
  end

  private def parse_signature(signature) : Hash(String, String)
    params = Hash(String, String).new

    signature.split(',') do |param|
      parts = param.split('=', 2)
      unless parts.size == 2
        error(400, "Invalid Signature: param #{param.strip.inspect} did not contain '='")
      end

      # This is an 'auth-param' defined in https://tools.ietf.org/html/rfc7235#section-2.1
      key = parts[0].strip
      value = parts[1].strip

      if value.starts_with? '"'
        unless value.ends_with?('"') && value.size > 2
          error(400, "Invalid Signature: malformed quoted-string in param #{param.strip.inspect}")
        end

        value = HTTP.dequote_string(value[1..-2]) rescue nil
        unless value
          error(400, "Invalid Signature: malformed quoted-string in param #{param.strip.inspect}")
        end
      end

      params[key] = value
    end

    params
  end

  private def cached_fetch_json(url, json_class : JsonType.class) : JsonType forall JsonType
    # TODO: actually cache this
    headers = HTTP::Headers{"Accept" => "application/activity+json, application/ld+json"}
    # TODO use HTTP::Client.new and set read timeout
    response = HTTP::Client.get(url, headers: headers)
    unless response.status_code == 200
      error(400, "Got non-200 response from fetching #{url.inspect}")
    end
    JsonType.from_json(response.body)
  end

  private def actor_from_key_id(key_id) : Actor
    # Signature keyId is actually the URL
    case key = cached_fetch_json(key_id, Actor | Key)
    when Key
      actor = cached_fetch_json(key.owner, Actor)
      actor.public_key = key
      actor
    when Actor
      key
    else
      raise "BUG: cached_fetch_json returned neither Actor nor Key"
    end
  rescue ex : JSON::Error
    error(400, "Invalid JSON from fetching #{key_id.inspect}\n#{ex.inspect_with_backtrace}")
  end

  private def build_signed_string(body, signed_headers)
    signed_headers ||= "date"

    signed_headers.split(' ').join('\n') do |header_name|
      case header_name
      when "(request-target)"
        "(request-target): #{request.method.downcase} #{request.resource}"
      when "digest"
        body_digest = OpenSSL::Digest.new("SHA256")
        body_digest.update(body)
        "digest: SHA-256=#{Base64.strict_encode(body_digest.digest)}"
      else
        request_header = request.headers[header_name]?
        unless request_header
          error(400, "Header #{header_name.inspect} was supposed to be signed but was missing from the request")
        end
        "#{header_name}: #{request_header}"
      end
    end
  end

  class Actor
    include JSON::Serializable

    getter id : String
    @[JSON::Field(key: "publicKey")]
    property public_key : Key
    getter endpoints : Endpoints?
    getter inbox : String

    def initialize(@id, @public_key, @endpoints, @inbox)
    end

    def inbox_url
      endpoints.try(&.shared_inbox) || inbox
    end

    def domain
      URI::Punycode.to_ascii(URI.parse(id).host.not_nil!.strip.downcase)
    end
  end

  struct Key
    include JSON::Serializable

    @[JSON::Field(key: "publicKeyPem")]
    getter public_key_pem : String
    getter owner : String

    def initialize(@public_key_pem : String, @owner)
    end
  end

  struct Endpoints
    include JSON::Serializable

    @[JSON::Field(key: "sharedInbox")]
    getter shared_inbox : String
  end

  private def error(status_code, message)
    response.status_code = status_code
    response.puts message

    raise InboxHandler::Error.new
  end

  private def request
    @context.request
  end

  private def response
    @context.response
  end
end
