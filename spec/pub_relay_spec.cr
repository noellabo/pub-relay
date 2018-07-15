require "./spec_helper"

describe PubRelay do
  describe "webfinger" do
    it "works" do
      status_code, body = request("GET", "/.well-known/webfinger?resource=acct%3Arelay%40example.com")
      status_code.should eq(200)
      body.should eq(<<-HERE)
      {"subject":"acct:relay@example.com","links":[{"rel":"self","type":"application/activity+json","href":"https://example.com/actor"}]}
      HERE
    end

    it "fails with resource parameter missing" do
      status_code, body = request("GET", "/.well-known/webfinger?resourc=misspelling")
      status_code.should eq(400)
      body.should contain("Resource query parameter not present")
    end

    it "handles not found resource parameter" do
      status_code, body = request("GET", "/.well-known/webfinger?resource=notrelay@example.com")
      status_code.should eq(404)
      body.should contain("Resource not found")
    end
  end

  it "serves actor" do
    status_code, body = request("GET", "/actor")
    status_code.should eq(200)

    pem_json = `openssl pkey -pubout < #{File.join(__DIR__, "test_actor.pem")}`.to_json
    body.should eq(<<-HERE)
      {"@context":["https://www.w3.org/ns/activitystreams","https://w3id.org/security/v1"],"id":"https://example.com/actor","type":"Service","preferredUsername":"relay","inbox":"https://example.com/inbox","publicKey":{"id":"https://example.com/actor#main-key","owner":"https://example.com/actor","publicKeyPem":#{pem_json}}}
      HERE
  end
end
