require "../spec_helper"

describe PubRelay::SubscriptionManager::DeliverWorker do
  it "delivers signed payloads" do
    integration_test do
      subscribe_domain("subscriber1.com")
      subscribe_domain("subscriber2.com")

      activity = PubRelay::Activity.new(
        id: "https://subscriber1.com/notes/1/create",
        type: "Create",
        published: Time.utc,
        object: "https://subscriber.com/notes/1",
        to: [PubRelay::Activity::PUBLIC_COLLECTION]
      )

      channel = Channel(Nil).new

      WebMock.stub("POST", "https://subscriber2.com/inbox")
        .to_return do |request|
          body = request.body.not_nil!.gets_to_end
          body.should eq(activity.to_json)

          request.body.not_nil!.rewind
          response = HTTP::Server::Response.new(IO::Memory.new)
          context = HTTP::Server::Context.new(request, response)
          PubRelay::WebServer::HTTPSignature.new(context, SPEC_REDIS).verify_signature

          channel.send nil

          HTTP::Client::Response.new(202)
        end

      signed_inbox_request(activity: activity, from: "subscriber1.com")

      channel.receive
    end
  end
end
