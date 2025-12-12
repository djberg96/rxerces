require 'spec_helper'

RSpec.describe RXerces::XML::Element do
  let(:xml) { '<root><child id="1">Text</child></root>' }
  let(:doc) { RXerces::XML::Document.parse(xml) }
  let(:element) { doc.root }

  it "is a subclass of Node" do
    expect(element).to be_a(RXerces::XML::Node)
    expect(element).to be_a(RXerces::XML::Element)
  end

  it "has a name" do
    expect(element.name).to eq('root')
  end

  it "can have attributes" do
    child = element.children.find { |n| n.is_a?(RXerces::XML::Element) }
    expect(child['id']).to eq('1')
  end

  it "can have children" do
    expect(element.children).not_to be_empty
  end
end
