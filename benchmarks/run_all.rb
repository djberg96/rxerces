#!/usr/bin/env ruby
# frozen_string_literal: true

# Run all benchmarks in sequence

benchmarks = %w[
  parse_benchmark.rb
  xpath_benchmark.rb
  css_benchmark.rb
  traversal_benchmark.rb
  serialization_benchmark.rb
]

puts "Running all RXerces benchmarks..."
puts "=" * 80
puts

benchmarks.each do |benchmark|
  puts "\nRunning #{benchmark}...\n\n"
  system("ruby -Ilib benchmarks/#{benchmark}")
  puts "\n"
end

puts "=" * 80
puts "All benchmarks complete!"
