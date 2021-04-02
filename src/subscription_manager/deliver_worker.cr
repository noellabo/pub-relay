require "circuit_breaker"

class PubRelay::SubscriptionManager::DeliverWorker
  record Delivery,
    message : String,
    domain : String,
    counter : Int32,
    accept : Bool

  include Earl::Artist(Delivery)

  getter domain : String

  def initialize(
    @domain : String,
    @inbox_url : URI,
    @relay_domain : String,
    @private_key : OpenSSL::PKey::RSA,
    @stats : Stats,
    @subscription_manager : SubscriptionManager
  )
    @mailbox = Channel(Delivery).new(100)
    @breaker = CircuitBreaker.new(
      threshold: 5,
      timewindow: 60,
      reenable_after: 300
    )
  end

  getter(client : HTTP::Client) do
    HTTP::Client.new(@inbox_url).tap do |client|
      client.dns_timeout = 5.seconds
      client.connect_timeout = 5.seconds
      client.read_timeout = 10.seconds
    end
  end

  def call(delivery : Delivery)
    if delivery.domain == @domain
      @stats.send Stats::DeliveryPayload.new(@domain, "SELF DOMAIN", delivery.counter)
      return
    end

    headers = request_headers(delivery)

    start_time = Time.monotonic
    begin
      response = client.post(@inbox_url.full_path, headers: headers, body: delivery.message)
    rescue
      @client = nil

      begin
        @breaker.run do
          response = client.post(@inbox_url.full_path, headers: headers, body: delivery.message)
        end
      rescue ex : CircuitOpenException | Socket::Error | IO::TimeoutError | OpenSSL::SSL::Error
        send_result(delivery, ex.inspect, start_time)
        return
      end
    end

    send_result(delivery, response.status_code, start_time)

    if delivery.accept && response.success?
      @subscription_manager.send SubscriptionManager::AcceptSent.new(@domain)
    end
  rescue ex
    @stats.send Stats::DeliveryPayload.new(@domain, ex.inspect, delivery.counter)
    raise ex
  end

  def send_result(delivery, status, start_time)
    time = Time.monotonic - start_time
    message = "POST #{@inbox_url} - #{status} (#{time.total_milliseconds}ms)"

    if status.is_a?(Int) && 200 <= status < 300
      log.debug message
    else
      log.info message
    end

    @stats.send Stats::DeliveryPayload.new(@domain, status.to_s, delivery.counter)
  end

  def request_headers(delivery)
    body_hash = OpenSSL::Digest.new("sha256")
    body_hash.update(delivery.message)
    body_hash = Base64.strict_encode(body_hash.digest)

    headers = HTTP::Headers{
      "Host"         => @inbox_url.host.not_nil!,
      "Date"         => HTTP.format_time(Time.utc),
      "Digest"       => "SHA-256=#{body_hash}",
      "Content-Type" => "application/ld+json;profile=\"https://www.w3.org/ns/activitystreams\"",
      "User-Agent"   => "pub-relay/#{PubRelay::VERSION} (https://#{@relay_domain})",
    }

    signed_headers = "(request-target) host date digest"
    signed_string = <<-END
      (request-target): post #{@inbox_url.path}
      host: #{headers["Host"]}
      date: #{headers["Date"]}
      digest: #{headers["Digest"]}
      END

    algorithm = "rsa-sha256"
    signature = @private_key.sign(OpenSSL::Digest.new("sha256"), signed_string)

    headers["Signature"] = %(keyId="https://#{@relay_domain}/actor",algorithm="#{algorithm}",headers="#{signed_headers}",signature="#{Base64.strict_encode(signature)}")

    headers
  end

  def reset
    @client = nil
  end

  def terminate
    @client.try(&.close)
  ensure
    @client = nil
  end

  private def route_url(path)
    "https://#{@domain}#{path}"
  end
end
