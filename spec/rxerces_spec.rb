require 'spec_helper'

RSpec.describe RXerces do
  it "has a version number" do
    expect(RXerces::VERSION).not_to be nil
  end

  describe ".XML" do
    it "parses XML string" do
      xml = '<root><child>text</child></root>'
      doc = RXerces.XML(xml)
      expect(doc).to be_a(RXerces::XML::Document)
    end
  end

  describe ".parse" do
    it "is an alias for .XML" do
      xml = '<root><child>text</child></root>'
      doc = RXerces.parse(xml)
      expect(doc).to be_a(RXerces::XML::Document)
    end
  end
end
