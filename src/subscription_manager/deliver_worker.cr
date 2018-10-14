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
    @private_key : OpenSSL::RSA,
    @stats : Stats,
    @subscription_manager : SubscriptionManager
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

    body_hash = OpenSSL::Digest.new("sha256")
    body_hash.update(delivery.message)
    body_hash = Base64.strict_encode(body_hash.digest)

    headers = HTTP::Headers{
      "Host"   => @inbox_url.host.not_nil!,
      "Date"   => HTTP.format_time(Time.utc_now),
      "Digest" => "SHA-256=#{body_hash}",
    }

    signed_headers = "(request-target) host date digest"
    signed_string = <<-END
      (request-target): post #{@inbox_url.path}
      host: #{headers["Host"]}
      date: #{headers["Date"]}
      digest: #{headers["Digest"]}
      END

    signature = @private_key.sign(OpenSSL::Digest.new("sha256"), signed_string)

    headers["Signature"] = %(keyId="https://#{@relay_domain}/actor",headers="#{signed_headers}",signature="#{Base64.strict_encode(signature)}")

    start_time = Time.monotonic
    begin
      response = client.post(@inbox_url.full_path, headers: headers, body: delivery.message)
    rescue
      @client = nil
      response = client.post(@inbox_url.full_path, headers: headers, body: delivery.message)
    end
    time = Time.monotonic - start_time

    if response.success?
      log.debug "POST #{@inbox_url} - #{response.status_code} (#{time.total_milliseconds}ms)"
    else
      log.info "POST #{@inbox_url} - #{response.status_code} (#{time.total_milliseconds}ms)"
    end

    @stats.send Stats::DeliveryPayload.new(@domain, response.status_code.to_s, delivery.counter)

    if delivery.accept
      @subscription_manager.send SubscriptionManager::AcceptSent.new(@domain)
    end
  rescue exception
    exception_code = exception.try(&.inspect) || "Exited"
    @stats.send Stats::DeliveryPayload.new(@domain, exception_code, delivery.counter)
    raise exception
  end

  def reset
    @client = nil
  end

  def terminate
    @client.try(&.close)
  ensure
    @client = nil
  end
end
