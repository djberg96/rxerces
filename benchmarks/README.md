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

## Native parsing investigation

`parse_overhead_benchmark.rb` and `native_parse_benchmark.cpp` use the same XML
fixture to compare Ruby API latency with direct Xerces parsing. The native
benchmark separates parser construction, parsing, and destruction, and compares
fresh/reused parsers with the default and DTD-only scanners.

The parsing speedup requires the experimental Xerces dependency build. Changes
to the benchmark scripts do not accelerate RXerces's normal installed parser.
For a direct before/after comparison using the two local investigation builds:

```bash
ruby benchmarks/compare_parsing.rb \
  /tmp/rxerces-xerces-stock \
  /tmp/rxerces-xerces-parse-investigation/build/src
```

This launches the exact same Ruby benchmark and XML fixtures in fresh processes
against each library. It verifies the loaded Xerces path using loader diagnostics,
prints the library hashes, alternates run order, and reports median before/after
times and speedups. It defaults to three runs per build; an optional final odd
integer changes that count. Both builds must have compatible Xerces ABIs and the
RXerces extension must already be compiled. The runner supports macOS and Linux
with glibc. The `/tmp` builds are local artifacts; recreate them as below if they
are no longer available.

```bash
ruby benchmarks/parse_overhead_benchmark.rb
c++ -O3 -std=c++11 benchmarks/native_parse_benchmark.cpp \
  $(pkg-config --cflags --libs xerces-c) -o /tmp/rxerces-native-parse-benchmark
/tmp/rxerces-native-parse-benchmark
```

The native benchmark accepts optional element count, iterations per sample, and
mode arguments. For example, `10000 120 default_fresh` runs a longer sample
suitable for profiling. Supported counts are 1, 100, 1000, and 10000; modes are
`default_fresh`, `default_reuse`, `dtd_fresh`, and `dtd_reuse`. It reports three
samples and selects the median by total time. The Ruby benchmark reports five
samples, forces GC between samples, and measures parse-call latency; forced
cleanup after each sample is outside the timed interval. Native timings include
document destruction. Tiny-document Ruby samples show substantial variation.

On macOS with Xerces 3.3.0, the medium/large Ruby timings closely matched direct
C++ parsing. Parser reuse nearly halved native cost for the 51-byte fixture but
did little for larger documents. Selecting the DTD-only scanner alone produced
only a small improvement. CPU sampling instead found repeated runtime type
checks in Xerces DOM construction, including `DOMParentNode::appendChildFast`.
Xerces's [DOM cast helpers](https://github.com/apache/xerces-c/blob/v3.3.0/src/xercesc/dom/impl/DOMCasts.hpp)
cross-cast between sibling base interfaces on these paths.

The experimental [Xerces patch](experiments/xerces-3.3-dom-casts.patch) first
attempts checked downcasts to the concrete element, text, and attribute
implementations. Other node kinds and implementations use the existing checked
fallback. It retains null/member checks and changes no class layouts or virtual
interfaces. This is a dependency prototype; RXerces does not automatically apply
it, and the installed Xerces library is unchanged.

The corresponding upstream change is [Apache Xerces-C PR #68](https://github.com/apache/xerces-c/pull/68),
submitted against the Xerces 4.0 development branch. The patch retained here is
the 3.3.0 experiment. Before testing a future Xerces release with RXerces, check
whether it includes the optimization and whether its ABI matches the compiled
extension and optional Xalan library. These tools do not upgrade dependencies.

Comparing stock and patched Xerces 3.3.0 Release builds made with the same compiler
(AppleClang 21), Ruby 4.0.10, and the same fixture produced these local median
Ruby parse-call times:

| Items | XML bytes | Stock Xerces | Patched Xerces | Speedup |
| --- | --- | --- | --- | --- |
| 100 | 3,813 | 163 µs | 54 µs | 3.0× |
| 1,000 | 38,013 | 1.55 ms | 0.51 ms | 3.0× |
| 10,000 | 380,013 | 15.30 ms | 4.95 ms | 3.1× |

Direct C++ parsing of the 10,000-item fixture similarly dropped from 15.23 to
4.99 ms. These results cover this macOS environment and generated fixture;
Linux and application-specific workloads still need evaluation. All 80 Xerces
CTest cases passed against the prototype, as did the 405-example RXerces suite
(0 failures, 2 expected pending examples) with Xalan enabled. The standalone
cast regression check covers const/mutable helpers, every DOM node kind, null
input, an unusual node-type hint, and null implementation members.

To reproduce the dependency experiment with separate stock and patched builds,
run from the RXerces checkout:

```bash
benchmark_repo="$PWD"
git clone --depth 1 --branch v3.3.0 https://github.com/apache/xerces-c.git /tmp/rxerces-xerces
cmake -S /tmp/rxerces-xerces -B /tmp/rxerces-xerces/build-stock \
  -DCMAKE_BUILD_TYPE=Release
cmake --build /tmp/rxerces-xerces/build-stock -j 4
git -C /tmp/rxerces-xerces apply \
  "$benchmark_repo/benchmarks/experiments/xerces-3.3-dom-casts.patch"
cmake -S /tmp/rxerces-xerces -B /tmp/rxerces-xerces/build-patched \
  -DCMAKE_BUILD_TYPE=Release
cmake --build /tmp/rxerces-xerces/build-patched -j 4
ruby benchmarks/compare_parsing.rb \
  /tmp/rxerces-xerces/build-stock/src /tmp/rxerces-xerces/build-patched/src
```

Keep the stock build as built before applying the patch. The measured macOS
builds additionally selected
`-Dtranscoder=macosunicodeconverter -Dnetwork-accessor=socket` for both builds.
To select a library manually, set `DYLD_LIBRARY_PATH` on macOS or
`LD_LIBRARY_PATH` on Linux to its build's `src` directory.

Validate the patched build with `ctest --test-dir /tmp/rxerces-xerces/build-patched
--output-on-failure -j 4`, and run RXerces's suite under the same library path.
On macOS the standalone cast check can be built and run with:

```bash
c++ -O3 -std=c++11 \
  -I/tmp/rxerces-xerces/src -I/tmp/rxerces-xerces/build-patched/src \
  benchmarks/experiments/dom_cast_regression.cpp \
  /tmp/rxerces-xerces/build-patched/src/libxerces-c-3.3.dylib \
  -Wl,-rpath,/tmp/rxerces-xerces/build-patched/src -o /tmp/rxerces-dom-cast-regression
/tmp/rxerces-dom-cast-regression
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

### 5. Serialization Benchmark (`serialization_benchmark.rb`)
Tests document serialization (`to_s`/`to_xml`) with various document sizes.

## Notes

- The comparison benchmarks use `benchmark-ips` with a 2-second warmup and 5-second measurement period
- `bindings_benchmark.rb` uses Ruby's standard library and three timed samples per operation
- Nokogiri and Ox tests are skipped if not installed
- RXerces requires Xalan-C for full XPath 1.0 support (CSS selectors need XPath)
