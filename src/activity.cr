require "./converters"

class Activity
  include JSON::Serializable

  @[JSON::Field(key: "type", converter: FuzzyStringArrayConverter)]
  getter types : Array(String)

  getter object : String | Object

  @[JSON::Field(key: "signature", converter: PresenceConverter)]
  getter? signature_present = false

  @[JSON::Field(converter: FuzzyStringArrayConverter)]
  getter to : Array(String)

  @[JSON::Field(converter: FuzzyStringArrayConverter)]
  getter cc : Array(String)

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

  class Object
    include JSON::Serializable

    getter id : String?

    @[JSON::Field(key: "type", converter: FuzzyStringArrayConverter)]
    getter types : Array(String)
  end
end
