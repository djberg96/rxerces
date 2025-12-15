require 'rxerces'

# Nokogiri compatibility module
# Provides drop-in replacement for Nokogiri XML parsing using RXerces
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
    Schema = RXerces::XML::Schema
  end

  # Nokogiri-compatible HTML module
  # Since RXerces uses Xerces-C which is an XML parser,
  # HTML parsing delegates to XML parsing
  module HTML
    # Parse HTML from a string - delegates to XML parsing
    # @param string [String] HTML string to parse
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

  # Top-level HTML parsing method
  # @param string [String] HTML string to parse
  # @return [RXerces::XML::Document] parsed document
  def self.HTML(string)
    RXerces::XML::Document.parse(string)
  end

  class << self
    alias_method :parse, :XML
  end
end
