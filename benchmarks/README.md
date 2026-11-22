# RXerces Performance Benchmarks

This directory contains performance benchmarks comparing RXerces with other popular Ruby XML libraries (Nokogiri and Ox).

## Setup

Install the required gems:

```bash
gem install benchmark-ips nokogiri ox
```

## Running Benchmarks

Run all benchmarks:

```bash
ruby benchmarks/parse_benchmark.rb
ruby benchmarks/xpath_benchmark.rb
ruby benchmarks/css_benchmark.rb
ruby benchmarks/traversal_benchmark.rb
ruby benchmarks/serialization_benchmark.rb
```

Or run a specific benchmark:

```bash
ruby benchmarks/parse_benchmark.rb
```

For a dependency-free benchmark of the native bindings, run:

```bash
bundle exec rake compile
ruby benchmarks/bindings_benchmark.rb > bindings-results.json
```

This reports median time per call and Ruby object allocations for parsing,
traversal, XPath, text extraction, and serialization at 100, 1,000, and 10,000
elements. It loads the extension from this checkout. Compare results using the
same Ruby, native libraries, and machine; set `BENCH_TIME=1` for longer samples.
Ruby allocation counts exclude memory allocated by Xerces and Xalan.

The sibling traversal optimization changes `children` and `element_children`
from repeated indexed DOM lookups to a single sibling walk. In a local Ruby
4.0.10/macOS run with Xalan enabled, accessing 10,000 children dropped from about
2.8 seconds to 1 millisecond. At 1,000 elements, serialization dropped from
298 to 238 microseconds. These are microbenchmark results, not application-wide
speedups. Parsing improved only slightly, and a separate repeated comparison
found full XPath query times roughly unchanged.

First/last element access now starts from the appropriate end without counting
all siblings. Xerces-only first-match XPath/CSS queries also avoid allocating
Ruby wrappers for the remaining matches; the native XPath snapshot still
contains all matches. Document serialization now writes UTF-8 bytes directly,
returns a UTF-8 Ruby string, and declares UTF-8 in the XML output.

## Benchmark Categories

### 1. Parse Benchmark (`parse_benchmark.rb`)
Tests XML document parsing performance with small, medium, and large documents.

### 2. XPath Benchmark (`xpath_benchmark.rb`)
Tests XPath query performance including:
- Simple queries (`//book`)
- Attribute-based queries (`//book[@category='fiction']`)
- Complex queries with predicates
- `at_xpath` for first-match queries

### 3. CSS Benchmark (`css_benchmark.rb`)
Tests CSS selector performance including:
- Simple selectors (`div`)
- Class selectors (`.title`)
- ID selectors (`#div100`)
- Descendant combinators (`div.content p.text`)
- `at_css` for first-match queries

### 4. Traversal Benchmark (`traversal_benchmark.rb`)
Tests DOM traversal operations:
- `.children` access
- `.element_children` access
- `.parent` access
- `.ancestors` access
- `.next_sibling` access
- `.text` extraction

### 5. Serialization Benchmark (`serialization_benchmark.rb`)
Tests document serialization (`to_s`/`to_xml`) with various document sizes.

## Notes

- The comparison benchmarks use `benchmark-ips` with a 2-second warmup and 5-second measurement period
- `bindings_benchmark.rb` uses Ruby's standard library and three timed samples per operation
- Nokogiri and Ox tests are skipped if not installed
- RXerces requires Xalan-C for full XPath 1.0 support (CSS selectors need XPath)
