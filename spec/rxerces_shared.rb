# frozen_string_literal: true

require 'rxerces'

RSpec.shared_examples RXerces do
  example 'version number is set to the expected value' do
    expect(RXerces::VERSION).to eq('0.4.0')
    expect(RXerces::VERSION).to be_frozen
  end
end
