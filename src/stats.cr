class PubRelay::Stats
  record HTTPResponsePayload,
    response_code : String,
    domain : String?

  record DeliveryPayload,
    domain : String,
    status_code : String,
    counter : Int32

  record DeliveryCounterPayload,
    counter : Int32

  record UnsubscribePayload,
    domain : String

  include Earl::Artist(HTTPResponsePayload | DeliveryPayload | DeliveryCounterPayload | UnsubscribePayload)

  @response_codes = Hash(String, Int32).new(default_value: 0)
  @response_codes_per_domain = Hash(String, Hash(String, Int32)).new do |hash, key|
    hash[key] = Hash(String, Int32).new(default_value: 0)
  end

  def call(response : HTTPResponsePayload)
    @response_codes[response.response_code] += 1
    @response_codes_per_domain[response.domain || "NO DOMAIN"][response.response_code] += 1
  end

  @delivery_codes = Hash(String, Int32).new(default_value: 0)
  @delivery_codes_per_domain = Hash(String, Hash(String, Int32)).new do |hash, key|
    hash[key] = Hash(String, Int32).new(default_value: 0)
  end

  @latest_delivery = -1
  @latest_delivery_per_domain = Hash(String, Int32).new(-1)

  def call(delivery : DeliveryPayload)
    @delivery_codes[delivery.status_code] += 1
    @delivery_codes_per_domain[delivery.domain][delivery.status_code] += 1

    prev_counter = @latest_delivery_per_domain[delivery.domain]
    if delivery.counter > prev_counter
      @latest_delivery_per_domain[delivery.domain] = delivery.counter
    else
      log.info "Message was delivered out of order for #{delivery.domain}"
    end
  end

  def call(payload : DeliveryCounterPayload)
    log.warn "Delivery counter went backwards!" unless payload.counter > @latest_delivery
    @latest_delivery = payload.counter
  end

  def call(unsubscribe : UnsubscribePayload)
    @delivery_codes_per_domain.delete(unsubscribe.domain)
    @latest_delivery_per_domain.delete(unsubscribe.domain)
  end

  def to_json(io)
    {
      response_codes:            @response_codes,
      response_codes_per_domain: @response_codes_per_domain,

      delivery_codes:            @delivery_codes,
      delivery_codes_per_domain: @delivery_codes_per_domain,

      deliver_count:  @latest_delivery,
      lag_per_domain: @latest_delivery_per_domain.transform_values { |count| @latest_delivery - count },
    }.to_json(io)
  end
end
