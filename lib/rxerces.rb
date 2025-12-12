require 'rxerces/rxerces'
require 'rxerces/version'

# Main module providing Nokogiri-compatible XML parsing using Xerces-C
module RXerces
  # Parse XML from a string
  # @param string [String] XML string to parse
  # @return [RXerces::XML::Document] parsed document
  def self.XML(string)
    RXerces::XML::Document.parse(string)
  end

  # Alias for compatibility
  class << self
    alias_method :parse, :XML
  end
end

# Nokogiri compatibility module
module Nokogiri
  # Nokogiri-compatible XML module
  module XML
    # Parse XML from a string - delegates to RXerces
    # @param string [String] XML string to parse
    # @return [RXerces::XML::Document] parsed document
    def self.parse(string)
      RXerces::XML::Document.parse(string)
    end

    # Alias Document class for compatibility
    Document = RXerces::XML::Document
    Node = RXerces::XML::Node
    Element = RXerces::XML::Element
    Text = RXerces::XML::Text
    NodeSet = RXerces::XML::NodeSet
  end

  # Top-level parse method for compatibility
  # @param string [String] XML string to parse
  # @return [RXerces::XML::Document] parsed document
  def self.XML(string)
    RXerces::XML::Document.parse(string)
  end

  class << self
    alias_method :parse, :XML
  end
end
