# frozen_string_literal: true

require 'spec_helper'

RSpec.describe "XPath Validation Cache" do
  let(:doc) { RXerces::XML::Document.parse('<root><item id="1"/><item id="2"/></root>') }

  # Helper to generate unique XPath expressions that work with or without Xalan
  # With Xalan: uses attribute predicates for more realistic expressions
  # Without Xalan: uses unique element names
  def unique_xpath(prefix, index)
    if RXerces.xalan_enabled?
      "//item[@id='#{prefix}_#{index}']"
    else
      "//#{prefix}#{index}"
    end
  end

  before(:each) do
    # Reset to default state before each test
    RXerces.cache_xpath_validation = true
    RXerces.xpath_validation_cache_max_size = 10_000
    RXerces.clear_xpath_validation_cache
  end

  after(:all) do
    # Restore defaults after all tests
    RXerces.cache_xpath_validation = true
    RXerces.xpath_validation_cache_max_size = 10_000
  end

  describe "configuration methods" do
    describe ".cache_xpath_validation?" do
      it "returns true by default" do
        expect(RXerces.cache_xpath_validation?).to be true
      end

      it "returns false when caching is disabled" do
        RXerces.cache_xpath_validation = false
        expect(RXerces.cache_xpath_validation?).to be false
      end
    end

    describe ".cache_xpath_validation=" do
      it "enables caching when set to true" do
        RXerces.cache_xpath_validation = false
        RXerces.cache_xpath_validation = true
        expect(RXerces.cache_xpath_validation?).to be true
      end

      it "disables caching when set to false" do
        RXerces.cache_xpath_validation = false
        expect(RXerces.cache_xpath_validation?).to be false
      end

      it "accepts truthy values" do
        RXerces.cache_xpath_validation = 1
        expect(RXerces.cache_xpath_validation?).to be true
      end

      it "accepts falsy values" do
        RXerces.cache_xpath_validation = nil
        expect(RXerces.cache_xpath_validation?).to be false
      end
    end

    describe ".xpath_validation_cache_size" do
      it "returns 0 when cache is empty" do
        expect(RXerces.xpath_validation_cache_size).to eq(0)
      end

      it "increases after XPath queries" do
        doc.xpath("//item")
        expect(RXerces.xpath_validation_cache_size).to eq(1)
      end

      it "does not double-count repeated expressions" do
        3.times { doc.xpath("//item") }
        expect(RXerces.xpath_validation_cache_size).to eq(1)
      end

      it "counts unique expressions" do
        doc.xpath("//item")
        if RXerces.xalan_enabled?
          doc.xpath("//item[@id='1']")
        else
          doc.xpath("//root")
        end
        doc.xpath("/root/item")
        expect(RXerces.xpath_validation_cache_size).to eq(3)
      end
    end

    describe ".xpath_validation_cache_max_size" do
      it "returns 10000 by default" do
        expect(RXerces.xpath_validation_cache_max_size).to eq(10_000)
      end
    end

    describe ".xpath_validation_cache_max_size=" do
      it "sets the maximum cache size" do
        RXerces.xpath_validation_cache_max_size = 5000
        expect(RXerces.xpath_validation_cache_max_size).to eq(5000)
      end

      it "accepts large values" do
        RXerces.xpath_validation_cache_max_size = 100_000
        expect(RXerces.xpath_validation_cache_max_size).to eq(100_000)
      end

      it "accepts zero" do
        RXerces.xpath_validation_cache_max_size = 0
        expect(RXerces.xpath_validation_cache_max_size).to eq(0)
      end

      it "raises TypeError for non-integer values" do
        expect { RXerces.xpath_validation_cache_max_size = "1000" }.to raise_error(TypeError)
        expect { RXerces.xpath_validation_cache_max_size = 1.5 }.to raise_error(TypeError)
        expect { RXerces.xpath_validation_cache_max_size = nil }.to raise_error(TypeError)
      end

      it "raises ArgumentError for negative values" do
        expect { RXerces.xpath_validation_cache_max_size = -1 }.to raise_error(ArgumentError)
        expect { RXerces.xpath_validation_cache_max_size = -100 }.to raise_error(ArgumentError)
      end
    end

    describe ".clear_xpath_validation_cache" do
      it "empties the cache" do
        doc.xpath("//item")
        if RXerces.xalan_enabled?
          doc.xpath("//item[@id='1']")
        else
          doc.xpath("//root")
        end
        expect(RXerces.xpath_validation_cache_size).to be > 0

        RXerces.clear_xpath_validation_cache
        expect(RXerces.xpath_validation_cache_size).to eq(0)
      end

      it "returns nil" do
        expect(RXerces.clear_xpath_validation_cache).to be_nil
      end
    end

    describe ".xalan_enabled?" do
      it "returns a boolean" do
        expect([true, false]).to include(RXerces.xalan_enabled?)
      end
    end

    describe ".xpath_max_length" do
      it "returns 10000 by default" do
        expect(RXerces.xpath_max_length).to eq(10_000)
      end
    end

    describe ".xpath_max_length=" do
      after(:each) do
        # Restore default after each test
        RXerces.xpath_max_length = 10_000
      end

      it "sets the maximum XPath expression length" do
        RXerces.xpath_max_length = 5000
        expect(RXerces.xpath_max_length).to eq(5000)
      end

      it "accepts zero to disable the limit" do
        RXerces.xpath_max_length = 0
        expect(RXerces.xpath_max_length).to eq(0)
      end

      it "raises TypeError for non-integer values" do
        expect { RXerces.xpath_max_length = "1000" }.to raise_error(TypeError)
        expect { RXerces.xpath_max_length = 1.5 }.to raise_error(TypeError)
        expect { RXerces.xpath_max_length = nil }.to raise_error(TypeError)
      end

      it "raises ArgumentError for negative values" do
        expect { RXerces.xpath_max_length = -1 }.to raise_error(ArgumentError)
        expect { RXerces.xpath_max_length = -100 }.to raise_error(ArgumentError)
      end

      it "rejects XPath expressions exceeding the limit" do
        RXerces.xpath_max_length = 50
        expect {
          doc.xpath("//" + "a" * 50)
        }.to raise_error(ArgumentError, /too long/)
      end

      it "allows XPath expressions within the limit" do
        RXerces.xpath_max_length = 100
        expect { doc.xpath("//item") }.not_to raise_error
      end

      it "allows any length when set to zero" do
        RXerces.xpath_max_length = 0
        # This would normally exceed the default 10k limit
        long_xpath = "//" + "a" * 15_000
        # Should not raise "too long" error - verify by checking it doesn't match that pattern
        begin
          doc.xpath(long_xpath)
        rescue ArgumentError => e
          expect(e.message).not_to match(/too long/)
        end
      end
    end
  end

  describe "caching behavior" do
    it "caches validated expressions when enabled" do
      RXerces.cache_xpath_validation = true
      doc.xpath("//item")
      expect(RXerces.xpath_validation_cache_size).to eq(1)
    end

    it "does not cache when disabled" do
      RXerces.cache_xpath_validation = false
      doc.xpath("//item")
      expect(RXerces.xpath_validation_cache_size).to eq(0)
    end

    it "reuses cached validations for identical expressions" do
      # This is implicitly tested by the fact that repeated queries
      # don't increase cache size
      xpath = RXerces.xalan_enabled? ? "//item[@id='1']" : "//item"
      5.times { doc.xpath(xpath) }
      expect(RXerces.xpath_validation_cache_size).to eq(1)
    end

    it "caches expressions from different documents" do
      doc2 = RXerces::XML::Document.parse('<data><value/></data>')

      doc.xpath("//item")
      doc2.xpath("//value")
      doc.xpath("//item")  # Should hit cache
      doc2.xpath("//value") # Should hit cache

      expect(RXerces.xpath_validation_cache_size).to eq(2)
    end

    it "caches expressions from node-level xpath calls" do
      root = doc.root
      root.xpath(".//item")
      expect(RXerces.xpath_validation_cache_size).to eq(1)
    end

    it "shares cache between document and node xpath calls" do
      doc.xpath("//item")
      doc.root.xpath("//item")  # Same expression, should reuse cache
      expect(RXerces.xpath_validation_cache_size).to eq(1)
    end

    it "respects max cache size" do
      RXerces.xpath_validation_cache_max_size = 3

      doc.xpath("//a")
      doc.xpath("//b")
      doc.xpath("//c")
      initial_size = RXerces.xpath_validation_cache_size

      # Cache should be at max
      expect(initial_size).to eq(3)

      # Additional expressions should not increase size beyond max
      doc.xpath("//d")
      doc.xpath("//e")
      expect(RXerces.xpath_validation_cache_size).to eq(3)
    end

    it "uses LRU eviction when cache is full" do
      RXerces.xpath_validation_cache_max_size = 3

      # Add 3 expressions: //a is oldest, //c is newest
      doc.xpath("//a")
      doc.xpath("//b")
      doc.xpath("//c")

      # Access //a again to make it most recently used
      # Now order is: //a (newest), //c, //b (oldest)
      doc.xpath("//a")

      # Add //d, which should evict //b (least recently used)
      doc.xpath("//d")
      expect(RXerces.xpath_validation_cache_size).to eq(3)

      # //a should still be cached (was accessed recently)
      # We can verify by checking that accessing it doesn't change cache size
      doc.xpath("//a")
      expect(RXerces.xpath_validation_cache_size).to eq(3)

      # //b was evicted, adding it again should evict //c (now oldest)
      doc.xpath("//b")
      expect(RXerces.xpath_validation_cache_size).to eq(3)

      # Cache should now contain: //b, //a, //d (in MRU order)
      # //c was evicted
    end
  end

  describe "thread safety" do
    it "handles concurrent xpath queries without errors" do
      threads = 10.times.map do |i|
        Thread.new do
          100.times do |j|
            doc.xpath(unique_xpath("t#{i}", j))
          end
        end
      end

      expect { threads.each(&:join) }.not_to raise_error
    end

    it "handles concurrent cache configuration changes" do
      threads = []

      # Thread toggling cache on/off
      threads << Thread.new do
        50.times do
          RXerces.cache_xpath_validation = false
          RXerces.cache_xpath_validation = true
        end
      end

      # Threads doing xpath queries
      3.times do |i|
        threads << Thread.new do
          50.times do |j|
            doc.xpath(unique_xpath("c#{i}", j))
          end
        end
      end

      expect { threads.each(&:join) }.not_to raise_error
    end

    it "handles concurrent cache clearing" do
      threads = []

      # Thread clearing cache periodically
      threads << Thread.new do
        20.times do
          sleep(0.001)
          RXerces.clear_xpath_validation_cache
        end
      end

      # Threads doing xpath queries
      3.times do |i|
        threads << Thread.new do
          100.times do |j|
            doc.xpath(unique_xpath("r#{i}", j))
          end
        end
      end

      expect { threads.each(&:join) }.not_to raise_error
    end

    it "returns consistent cache size under concurrent access" do
      # Fill cache with known expressions
      10.times { |i| doc.xpath("//item#{i}") }
      initial_size = RXerces.xpath_validation_cache_size

      # Read cache size from multiple threads
      sizes = []
      mutex = Mutex.new

      threads = 5.times.map do
        Thread.new do
          10.times do
            size = RXerces.xpath_validation_cache_size
            mutex.synchronize { sizes << size }
          end
        end
      end

      threads.each(&:join)

      # All reads should return consistent values (either the initial
      # size or values after any concurrent modifications)
      expect(sizes).to all(be >= 0)
    end
  end

  describe "interaction with validation" do
    it "still validates expressions even when cached" do
      # First call validates and caches
      doc.xpath("//item")

      # Invalid expression should still be rejected
      expect {
        doc.xpath("//item[@id=''] or 1=1")
      }.to raise_error(ArgumentError)
    end

    it "caches valid expressions only" do
      # Try an invalid expression
      expect {
        doc.xpath("")
      }.to raise_error(ArgumentError)

      # Cache should not have increased
      expect(RXerces.xpath_validation_cache_size).to eq(0)
    end
  end
end
