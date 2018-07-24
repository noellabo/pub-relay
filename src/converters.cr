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
