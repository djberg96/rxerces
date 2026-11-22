#!/usr/bin/env ruby
# frozen_string_literal: true

require 'digest'
require 'json'
require 'open3'
require 'rbconfig'

unless ARGV.size.between?(2, 3)
  abort "Usage: ruby #{$PROGRAM_NAME} STOCK_LIBRARY_DIR PATCHED_LIBRARY_DIR [RUNS=3]"
end

directories = { before: File.realpath(ARGV[0]), after: File.realpath(ARGV[1]) }
runs = Integer(ARGV.fetch(2, '3'))
abort 'RUNS must be positive and odd' unless runs.positive? && runs.odd?

if RUBY_PLATFORM.include?('darwin')
  loader, trace, trace_value = 'DYLD_LIBRARY_PATH', 'DYLD_PRINT_LIBRARIES', '1'
  library_pattern = /^dyld\[\d+\]: <[^>]+> (\/[^\n]*\/libxerces-c[^\/\n]*\.dylib)$/
elsif RUBY_PLATFORM.include?('linux')
  loader, trace, trace_value = 'LD_LIBRARY_PATH', 'LD_DEBUG', 'libs'
  library_pattern = /calling init:\s*(\/[^\n]*\/libxerces-c[^\/\n]*\.so[^\s]*)/
else
  abort 'Library verification currently supports macOS and Linux with glibc'
end

benchmark = File.expand_path('parse_overhead_benchmark.rb', __dir__)
results = { before: [], after: [] }
libraries = {}
runs.times do |run|
  # Alternate order to reduce bias from CPU temperature and background work.
  order = run.even? ? [:before, :after] : [:after, :before]
  order.each do |variant|
    warn "Run #{run + 1}/#{runs}: #{variant}"
    output, diagnostics, status = Open3.capture3(
      { loader => directories.fetch(variant), trace => trace_value },
      RbConfig.ruby, benchmark
    )
    abort "#{variant} benchmark failed:\n#{diagnostics}" unless status.success?
    loaded = diagnostics.scan(library_pattern).flatten.map { |path| File.realpath(path) }.uniq
    unless loaded.size == 1 && File.dirname(loaded.first) == directories.fetch(variant)
      abort "Could not verify #{variant} Xerces in #{directories.fetch(variant)}. Loaded: #{loaded.inspect}"
    end
    libraries[variant] = loaded.first
    results.fetch(variant) << JSON.parse(output)
  end
end

all_results = results.values.flatten
reference = all_results.first
workloads = reference.fetch('measurements').map { |m| m.values_at('elements', 'bytes', 'iterations') }
all_results.each do |result|
  actual = result.fetch('measurements').map { |m| m.values_at('elements', 'bytes', 'iterations') }
  unless actual == workloads && result.values_at('ruby', 'xalan') == reference.values_at('ruby', 'xalan')
    abort 'Ruby, Xalan configuration, or benchmark workloads differ between runs'
  end
end

puts reference.fetch('ruby')
libraries.each do |variant, path|
  puts "#{variant}: #{path} (SHA256 #{Digest::SHA256.file(path).hexdigest[0, 12]})"
end
puts "Same benchmark and XML; median of #{runs} runs, each with five samples. Times are microseconds per parse."
puts format('%8s %10s %12s %12s %10s', 'Items', 'XML bytes', 'Before', 'After', 'Speedup')
workloads.each_with_index do |(elements, bytes, _iterations), index|
  times = results.transform_values do |samples|
    samples.map { |sample| sample.fetch('measurements')[index].fetch('median_microseconds') }.sort[runs / 2]
  end
  puts format('%8d %10d %12.2f %12.2f %9.2fx', elements, bytes, times.fetch(:before),
              times.fetch(:after), times.fetch(:before) / times.fetch(:after))
end
