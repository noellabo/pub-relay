class PubRelay::Activity
  include JSON::Serializable

  getter id : String
  getter object : String | Object
  getter published : Time?

  getter duplicate : Bool?

  @[JSON::Field(key: "type", converter: PubRelay::Activity::FuzzyStringArrayConverter)]
  getter types : Array(String)

  @[JSON::Field(key: "signature", converter: PubRelay::Activity::PresenceConverter)]
  getter? signature_present = false

  @[JSON::Field(converter: PubRelay::Activity::FuzzyStringArrayConverter)]
  getter to = [] of String

  @[JSON::Field(converter: PubRelay::Activity::FuzzyStringArrayConverter)]
  getter cc = [] of String

  def initialize(*, @id, @object, @published, @types, @to = [] of String, @cc = [] of String)
  end

  def initialize(*, @id, @object, @published, type, @to = [] of String, @cc = [] of String)
    @types = [type]
  end

  def check_duplicate?(redis)
    d = @duplicate
    return d unless d.nil?

    @duplicate = redis.zadd("activity_id", (@published || Time.utc).to_unix_f.to_s, @id, nx: true) == 0
  end

  def follow?
    types.includes? "Follow"
  end

  def unfollow?
    if obj = object.as? Object
      types.includes?("Undo") && obj.types.includes?("Follow")
    else
      false
    end
  end

  def accept?
    types.includes? "Accept"
  end

  def reject?
    types.includes? "Reject"
  end

  PUBLIC_COLLECTION = "https://www.w3.org/ns/activitystreams#Public"

  def object_id
    case object = @object
    when String
      object
    when Object
      object.id
    end
  end

  def addressed_to_public?
    to.includes?(PUBLIC_COLLECTION) || cc.includes?(PUBLIC_COLLECTION)
  end

  FORWARD_TYPES = {"Update", "Delete", "Undo", "Move", "Like", "Add", "Remove"}
  RELAY_TYPES   = {"Create", "Announce"}

  def valid_for_rebroadcast?
    addressed_to_public? && (
      types.any? { |type| FORWARD_TYPES.includes? type } ||
        signature_present? && types.any? { |type| RELAY_TYPES.includes? type }
    )
  end

  def valid_for_relay?
    types.any? { |type| RELAY_TYPES.includes? type }
  end

  def older_published?
    published.nil? || published.not_nil! < Time.utc - 30.minutes
  end

  class Object
    include JSON::Serializable

    getter id : String

    @[JSON::Field(key: "type", converter: PubRelay::Activity::FuzzyStringArrayConverter)]
    getter types : Array(String)
  end

  module PresenceConverter
    def self.from_json(pull) : Bool
      present = pull.kind != JSON::PullParser::Kind::Null
      pull.skip
      present
    end

    def self.to_json(value, json : JSON::Builder)
      json.bool value
    end
  end

  module FuzzyStringArrayConverter
    def self.from_json(pull) : Array(String)
      strings = Array(String).new

      case pull.kind
      when JSON::PullParser::Kind::BeginArray
        pull.read_array do
          if string = pull.read? String
            strings << string
          else
            pull.skip
          end
        end
      else
        strings << pull.read_string
      end

      strings
    end

    def self.to_json(array, json)
      array.to_json(json)
    end
  end
end
