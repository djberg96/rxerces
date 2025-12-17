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
ruby benchmarks/micro/run_all.rb
```

Or run a specific benchmark:

```bash
ruby benchmarks/parse_benchmark.rb
```

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

### 6. Microbenchmarks (`benchmarks/micro/*`)
Fine-grained method-level benchmarks to track improvements and identify hotspots:
- `Node#children`, `Node#element_children`
- `Node#parent`, `Node#ancestors`
- `Node#next_sibling`, `Node#previous_sibling`
- `Node#attributes`, `Node#[]`, `Node#[]=`
- `Node#inner_html`, `Node#path`, `Node#blank?`
- `Document#at_xpath`, `Document#xpath`, `Document#css`
- `Document#to_s` serialization

Run all microbenchmarks:

```bash
ruby benchmarks/micro/run_all.rb
```

### 5. Serialization Benchmark (`serialization_benchmark.rb`)
Tests document serialization (`to_s`/`to_xml`) with various document sizes.

## Notes

- All benchmarks use `benchmark-ips` for accurate iterations-per-second measurements
- Each benchmark runs with a 2-second warmup and 5-second measurement period
- Nokogiri and Ox tests are skipped if not installed
- RXerces requires Xalan-C for full XPath 1.0 support (CSS selectors need XPath)
