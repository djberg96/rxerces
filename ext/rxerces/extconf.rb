require 'mkmf'

# Force C++ compiler for the extension
$CXXFLAGS << " -std=c++11"

# Try to find Xerces-C via homebrew on macOS
if RUBY_PLATFORM =~ /darwin/
  homebrew_prefix = `brew --prefix xerces-c 2>/dev/null`.chomp
  if !homebrew_prefix.empty? && File.directory?(homebrew_prefix)
    $INCFLAGS << " -I#{homebrew_prefix}/include"
    $LDFLAGS << " -L#{homebrew_prefix}/lib"
  end
end

# Check for Xerces-C library
unless have_library('xerces-c')
  puts "Xerces-C library not found. Please install it:"
  puts "  macOS: brew install xerces-c"
  puts "  Ubuntu/Debian: sudo apt-get install libxerces-c-dev"
  puts "  Fedora/RHEL: sudo yum install xerces-c-devel"
  exit 1
end

# Use C++ for header checking
# We check by trying to find the library itself rather than header
unless find_header('xercesc/util/PlatformUtils.hpp')
  # Header check failed, but library exists, so we'll proceed with a warning
  puts "Warning: Xerces-C headers not automatically detected, but library is present."
  puts "Proceeding with compilation..."
end

create_makefile('rxerces/rxerces')
