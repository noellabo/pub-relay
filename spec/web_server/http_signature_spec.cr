require "../spec_helper"

private def post_inbox(headers, body = nil)
  request("POST", "/inbox", headers, body)
end

private def post_signature(signature, body = nil)
  request("POST", "/inbox", HTTP::Headers{"Signature" => signature}, body)
end

private def expect_signature_fails(signature_header, expected_body)
  it "fails to parse Signature => #{signature_header.inspect}" do
    status_code, body = post_signature(signature_header)
    status_code.should eq(400)
    body.should contain(expected_body)
  end
end

private alias HTTPSignature = PubRelay::WebServer::HTTPSignature

private def sir_boops_actor
  HTTPSignature::Actor.new(
    id: "https://mastodon.sergal.org/users/Sir_Boops",
    public_key: HTTPSignature::Key.new(
      public_key_pem: <<-KEY,
            -----BEGIN PUBLIC KEY-----
            MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAvwDujxmxoYHs64MyVB3L
            G5ZyBxV3ufaMRBFu42bkcTpISq1WwZ+3Zb6CI8zOO+nM+Q2llrVRYjZa4ZFnOLvM
            Tq/Kf+Zf5wy2aCRer88gX+MsJOAtItSi412y0a/rKOuFaDYLOLeTkRvmGLgZWbsr
            ZJOp+YWb3zQ5qsIOInkc5BwI172tMsGeFtsnbNApPV4lrmtTGaJ8RiM8MR7XANBO
            fOHggSt1+eAIKGIsCmINEMzs1mG9D75xKtC/sM8GfbvBclQcBstGkHAEj1VHPW0c
            h6Bok5/QQppicyb8UA1PAA9bznSFtKlYE4xCH8rlCDSDTBRtdnBWHKcj619Ujz4Q
            awIDAQAB
            -----END PUBLIC KEY-----
            KEY
      owner: "https://mastodon.sergal.org/users/Sir_Boops"
    ),
    endpoints: nil,
    inbox: "https://example.com/inbox"
  )
end

describe PubRelay::WebServer::HTTPSignature do
  it "fails unsigned requests" do
    status_code, body = post_inbox(HTTP::Headers{"Signatur" => "typo"})
    status_code.should eq(401)
    body.should contain("no Signature header")
  end

  expect_signature_fails("", "did not contain '='")
  expect_signature_fails("foo=bar, foo2", %q(param "foo2" did not contain '='))
  expect_signature_fails(%q(foo="), %q(malformed quoted-string))
  expect_signature_fails(%q(foo="bar), %q(malformed quoted-string))
  expect_signature_fails(%q(foo="bar\"), %q(malformed quoted-string))
  expect_signature_fails(%q(foo=1, bar=", baz=2), %q(malformed quoted-string in param "bar=\""))

  it "fails requests without keyId or signature" do
    status_code, body = post_signature(%q(ketId="typo", signature="base64"))
    status_code.should eq(400)
    body.should contain("keyId not present")

    status_code, body = post_signature(%q(keyId="typo", signatur="base64"))
    status_code.should eq(400)
    body.should contain("signature not present")
  end

  it "fails with 404 response from keyId URL" do
    WebMock.wrap do
      WebMock.stub("GET", "https://example.com/key")
        .to_return(status: 404, body: sir_boops_actor.to_json)

      status_code, body = post_signature(%q(keyId="https://example.com/key", signature="a"))

      status_code.should eq(400)
      body.should contain(%q(Got non-200 response from fetching "https://example.com/key"))
    end
  end

  it "fails with invalid JSON from keyId URL" do
    WebMock.wrap do
      WebMock.stub("GET", "https://example.com/key")
        .to_return(body: sir_boops_actor.to_json.gsub('"', '\''))

      status_code, body = post_signature(%q(keyId="https://example.com/key", signature="a"))

      status_code.should eq(400)
      body.should contain(%q(Invalid JSON from fetching "https://example.com/key"))
    end
  end

  it "succeeds with empty endpoints object" do
    File.open("spec/data/actor_empty_endpoints.json") do |file|
      actor = Union(HTTPSignature::Actor, HTTPSignature::Key).from_json(file).as(HTTPSignature::Actor)
      actor.inbox_url.should eq("https://microblog.pub/inbox")
    end
  end

  it "fails with no request body" do
    WebMock.wrap do
      WebMock.stub("GET", "https://example.com/key")
        .to_return(body: sir_boops_actor.to_json)

      status_code, body = post_signature(%q(keyId="https://example.com/key", signature="a"))

      status_code.should eq(400)
      body.should contain(%q(No request body))
    end
  end

  it "fails with extremely large request body" do
    WebMock.wrap do
      WebMock.stub("GET", "https://example.com/key")
        .to_return(body: sir_boops_actor.to_json)

      File.open("/dev/zero") do |zeroes|
        status_code, body = post_signature(%q(keyId="https://example.com/key", signature="a"), body: zeroes)

        status_code.should eq(400)
        body.should contain(%q(Request body too large))
      end
    end
  end

  it "fails with invalid signature base64" do
    WebMock.wrap do
      WebMock.stub("GET", "https://mastodon.sergal.org/users/Sir_Boops#main-key")
        .to_return(body: sir_boops_actor.to_json)

      File.open("spec/data/signed_post_bad_base64.http") do |file|
        signed_request = HTTP::Request.from_io(file).as(HTTP::Request)
        status_code, body = post_inbox(signed_request.headers, signed_request.body)

        status_code.should eq(400)
        body.should contain("Invalid base64")
      end
    end
  end

  it "successfully validates a signature from actor" do
    WebMock.wrap do
      WebMock.stub("GET", "https://mastodon.sergal.org/users/Sir_Boops#main-key")
        .to_return(body: sir_boops_actor.to_json)

      File.open("spec/data/signed_post.http") do |file|
        signed_request = HTTP::Request.from_io(file).as(HTTP::Request)
        status_code, body = post_inbox(signed_request.headers, signed_request.body)

        status_code.should eq(202)
      end
    end
  end

  it "successfully validates a signature from key" do
    WebMock.wrap do
      WebMock.stub("GET", "https://mastodon.sergal.org/users/Sir_Boops")
        .to_return(body: sir_boops_actor.to_json)

      WebMock.stub("GET", "https://mastodon.sergal.org/keys/Sir_Boops")
        .to_return(body: sir_boops_actor.public_key.to_json)

      File.open("spec/data/signed_post_keyurl.http") do |file|
        signed_request = HTTP::Request.from_io(file).as(HTTP::Request)
        status_code, body = post_inbox(signed_request.headers, signed_request.body)

        status_code.should eq(202)
      end
    end
  end

  it "fails to validate a modified signature" do
    WebMock.wrap do
      WebMock.stub("GET", "https://mastodon.sergal.org/users/Sir_Boops#main-key")
        .to_return(body: sir_boops_actor.to_json)

      File.open("spec/data/signed_post_bad_signature.http") do |file|
        signed_request = HTTP::Request.from_io(file).as(HTTP::Request)
        status_code, body = post_inbox(signed_request.headers, signed_request.body)

        status_code.should eq(401)
        body.should contain(%q(cryptographic signature did not verify for "https://mastodon.sergal.org/users/Sir_Boops#main-key"))
      end
    end
  end

  it "fails to validate with a tampered body" do
    WebMock.wrap do
      WebMock.stub("GET", "https://mastodon.sergal.org/users/Sir_Boops#main-key")
        .to_return(body: sir_boops_actor.to_json)

      File.open("spec/data/signed_post_tampered.http") do |file|
        signed_request = HTTP::Request.from_io(file).as(HTTP::Request)
        status_code, body = post_inbox(signed_request.headers, signed_request.body)

        status_code.should eq(401)
        body.should contain(%q(cryptographic signature did not verify for "https://mastodon.sergal.org/users/Sir_Boops#main-key"))
      end
    end
  end

  it "fails to validate with missing headers" do
    WebMock.wrap do
      WebMock.stub("GET", "https://mastodon.sergal.org/users/Sir_Boops#main-key")
        .to_return(body: sir_boops_actor.to_json)

      File.open("spec/data/signed_post_missing_header.http") do |file|
        signed_request = HTTP::Request.from_io(file).as(HTTP::Request)
        status_code, body = post_inbox(signed_request.headers, signed_request.body)

        status_code.should eq(400)
        body.should contain(%q(Header "user-agent" was supposed to be signed but was missing from the request))
      end
    end
  end
end
