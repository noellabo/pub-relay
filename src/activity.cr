require "./converters"

class Activity
  include JSON::Serializable

  @[JSON::Field(key: "type", converter: FuzzyStringArrayConverter)]
  getter types : Array(String)

  getter object : String | Object

  @[JSON::Field(key: "signature", converter: PresenceConverter)]
  getter? signature_present = false

  @[JSON::Field(converter: FuzzyStringArrayConverter)]
  getter to = [] of String

  @[JSON::Field(converter: FuzzyStringArrayConverter)]
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

    @[JSON::Field(key: "type", converter: FuzzyStringArrayConverter)]
    getter types : Array(String)
  end
end
