require 'rxerces/rxerces'
require 'rxerces/version'

# Main module providing Nokogiri-compatible XML parsing using Xerces-C
module RXerces
  # Parse XML from a string
  # @param string [String] XML string to parse
  # @param options [Hash] parsing options
  # @return [RXerces::XML::Document] parsed document
  def self.XML(string, **options)
    RXerces::XML::Document.parse(string, **options)
  end

  # Alias for compatibility
  class << self
    alias_method :parse, :XML
  end
end
