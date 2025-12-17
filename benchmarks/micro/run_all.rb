#!/usr/bin/env ruby
# frozen_string_literal: true

# Run all microbenchmarks in sequence

benchmarks = %w[
  node_methods_benchmark.rb
]

puts "Running all RXerces microbenchmarks..."
puts "=" * 80
puts

benchmarks.each do |benchmark|
  puts "\nRunning #{benchmark}...\n\n"
  system("ruby -Ilib benchmarks/micro/#{benchmark}")
  puts "\n"
end

puts "=" * 80
puts "All microbenchmarks complete!"
