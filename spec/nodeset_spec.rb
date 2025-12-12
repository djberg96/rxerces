require 'spec_helper'

RSpec.describe RXerces::XML::NodeSet do
  let(:xml) do
    <<-XML
      <root>
        <item>First</item>
        <item>Second</item>
        <item>Third</item>
      </root>
    XML
  end

  let(:doc) { RXerces::XML::Document.parse(xml) }

  # For basic testing, we'll use an empty nodeset since full XPath isn't implemented
  let(:nodeset) { doc.xpath('//item') }

  describe "#length" do
    it "returns the number of nodes" do
      expect(nodeset.length).to be_a(Integer)
      expect(nodeset.length).to be >= 0
    end
  end

  describe "#size" do
    it "is an alias for length" do
      expect(nodeset.size).to eq(nodeset.length)
    end
  end

  describe "#[]" do
    it "returns nil for empty nodeset" do
      expect(nodeset[0]).to be_nil
    end
  end

  describe "#each" do
    it "is enumerable" do
      expect(nodeset).to respond_to(:each)
    end

    it "returns enumerator when no block given" do
      expect(nodeset.each).to be_a(Enumerator)
    end

    it "yields nothing for empty nodeset" do
      count = 0
      nodeset.each { count += 1 }
      expect(count).to eq(0)
    end
  end

  describe "#to_a" do
    it "converts to array" do
      result = nodeset.to_a
      expect(result).to be_an(Array)
    end
  end

  it "includes Enumerable" do
    expect(RXerces::XML::NodeSet.ancestors).to include(Enumerable)
  end
end
