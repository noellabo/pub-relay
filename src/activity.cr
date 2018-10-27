class PubRelay::Activity
  include JSON::Serializable

  getter id : String
  getter object : String | Object

  @[JSON::Field(key: "type", converter: PubRelay::Activity::FuzzyStringArrayConverter)]
  getter types : Array(String)

  @[JSON::Field(converter: PubRelay::Activity::FuzzyStringArrayConverter)]
  getter to = [] of String

  @[JSON::Field(converter: PubRelay::Activity::FuzzyStringArrayConverter)]
  getter cc = [] of String

  def initialize(*, @id, @object, @types, @to = [] of String, @cc = [] of String)
  end

  def initialize(*, @id, @object, type, @to = [] of String, @cc = [] of String)
    @types = [type]
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

  VALID_TYPES = {"Create", "Update", "Delete", "Announce", "Undo"}

  def valid_for_rebroadcast?
    addressed_to_public? && types.any? { |type| VALID_TYPES.includes? type }
  end

  class Object
    include JSON::Serializable

    getter id : String

    @[JSON::Field(key: "type", converter: PubRelay::Activity::FuzzyStringArrayConverter)]
    getter types : Array(String)
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

    def self.to_json(array, json)
      array.to_json(json)
    end
  end
end
