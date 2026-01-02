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

  describe "thread safety" do
    it "handles concurrent initialization safely" do
      xml = '<root><child>text</child></root>'
      threads = []
      results = []

      # Create multiple threads that parse XML concurrently
      10.times do
        threads << Thread.new do
          doc = RXerces.XML(xml)
          results << doc.class
        end
      end

      # Wait for all threads to complete
      threads.each(&:join)

      # All should succeed and return Document objects
      expect(results.size).to eq(10)
      results.each do |result|
        expect(result).to eq(RXerces::XML::Document)
      end
    end
  end
end
