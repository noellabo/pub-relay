class PubRelay::Activity
  include JSON::Serializable

  getter id : String?
  getter object : String | Object

  @[JSON::Field(key: "type", converter: PubRelay::Activity::FuzzyStringArrayConverter)]
  getter types : Array(String)

  @[JSON::Field(key: "signature", converter: PubRelay::Activity::PresenceConverter)]
  getter? signature_present = false

  @[JSON::Field(converter: PubRelay::Activity::FuzzyStringArrayConverter)]
  getter to = [] of String

  @[JSON::Field(converter: PubRelay::Activity::FuzzyStringArrayConverter)]
  getter cc = [] of String

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

  PUBLIC_COLLECTION = "https://www.w3.org/ns/activitystreams#Public"

  def object_is_public_collection?
    case object = @object
    when String
      object == PUBLIC_COLLECTION
    when Object
      object.id == PUBLIC_COLLECTION
    end
  end

  def addressed_to_public?
    to.includes?(PUBLIC_COLLECTION) || cc.includes?(PUBLIC_COLLECTION)
  end

  VALID_TYPES = {"Create", "Update", "Delete", "Announce", "Undo"}

  def valid_for_rebroadcast?
    signature_present? && addressed_to_public? && types.any? { |type| VALID_TYPES.includes? type }
  end

  class Object
    include JSON::Serializable

    getter id : String?

    @[JSON::Field(key: "type", converter: PubRelay::Activity::FuzzyStringArrayConverter)]
    getter types : Array(String)
  end

  module PresenceConverter
    def self.from_json(pull) : Bool
      present = pull.kind != :null
      pull.skip
      present
    end
  end

  module FuzzyStringArrayConverter
    def self.from_json(pull) : Array(String)
      strings = Array(String).new

      case pull.kind
      when :begin_array
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
  end
end
