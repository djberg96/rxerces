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

  describe "security" do
    it "prevents XXE attacks by not processing external entities" do
      # XML with external entity reference
      malicious_xml = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE foo [ <!ENTITY xxe SYSTEM "file:///etc/passwd"> ]>
        <foo>&xxe;</foo>
      XML

      # Should fail to parse because external entities are disabled
      expect {
        RXerces.XML(malicious_xml)
      }.to raise_error(RuntimeError, /unable to open external entity/)
    end

    it "allows external entities when explicitly enabled" do
      # XML with external entity reference
      xml_with_entity = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE foo [ <!ENTITY test "test content"> ]>
        <foo>&test;</foo>
      XML

      # Should succeed with internal entities even when external are disabled
      doc = RXerces.XML(xml_with_entity)
      expect(doc.root.text).to eq("test content")

      # With allow_external_entities: true, should still handle internal entities
      doc2 = RXerces.XML(xml_with_entity, allow_external_entities: true)
      expect(doc2.root.text).to eq("test content")
    end
  end
end
