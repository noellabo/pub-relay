class PubRelay::Stats
  record HTTPResponsePayload,
    response_code : String,
    domain : String?

  include Earl::Artist(HTTPResponsePayload)

  @response_codes = Hash(String, Int32).new(default_value: 0)
  @response_codes_per_domain = Hash(String, Hash(String, Int32)).new do |hash, key|
    hash[key] = Hash(String, Int32).new(default_value: 0)
  end

  def call(response : HTTPResponsePayload)
    @response_codes[response.response_code] += 1
    @response_codes_per_domain[response.domain || "NO DOMAIN"][response.response_code] += 1
  end

  def to_json(io)
    {
      response_codes:            @response_codes,
      response_codes_per_domain: @response_codes_per_domain,
    }.to_json(io)
  end
end
