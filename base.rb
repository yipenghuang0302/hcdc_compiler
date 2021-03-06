#!/usr/bin/env ruby

require 'pp'
require 'optparse'

$help = nil
DIFFEQ_ARGS = {
  :verbose => false,
  :readouts => [],
  :quiet => true,
  :kfan => 3,
  :file => nil,
  :describe => false
}

# Process args 
def process_args(klass)
  options = OptionParser.new {|opts|
    opts.banner = "Usage: #{File.basename($0)} [options]"

    opts.on("-v", "--verbose", "Print descriptions at each stage.") {
      DIFFEQ_ARGS[:verbose] = true
    } unless klass.ignore?(:verbose)

    opts.on("-n", "--noisy", "Print information during diffeq parsing.") {
      DIFFEQ_ARGS[:quiet] = false
    } unless klass.ignore?(:quiet)

    opts.on("-o", "--output", "Output to the given C file.") {|file|
      DIFFEQ_ARGS[:file] = file
    } unless klass.ignore?(:file)

    opts.on("-k", "--kfans", "Select fanout for fans.") {|fanout|
      error("Fanout must be an integer > 1, but is `#{fanout}' instead.", 1) unless fanout =~ /^\d+$/ && fanout.to_i > 1
      DIFFEQ_ARGS[:kfan] = fanout.to_i
    } unless klass.ignore?(:kfan)

    opts.on_tail("-h", "--help", "Show this message.") {
      $stdout.puts opts
      DIFFEQ_ARGS[:describe] = true
    }
  }

  $help = options.help
  options.parse!

  readouts, args = ARGV.partition {|a| a =~ /^\d+$/}
  DIFFEQ_ARGS[:readouts] = readouts.map {|i| i.to_i}.sort.uniq
  klass.ignore?(:readouts) ? ARGV : args
end

# Error handling
def error(msg, code, backtrace=false)
  $stderr.puts("ERROR: #{msg}")
  $stderr.puts caller if backtrace
  exit(code)
end

# Read in a differential equiation from the user and return it, exiting if nothing was given.
def readDiffEq
  $stdout.print("Please enter a differential equation to compile: ") if $stdin.tty?
  diffeq = $stdin.gets.chomp.strip
  error("Empty differential equation; terminating.", -1) if diffeq =~ /^\s*$/
  diffeq
end

# Write out descriptions if requested
class Class
  def describe
    if DIFFEQ_ARGS[:verbose] then
      $stdout.puts "## #{self.source}"
      $stdout.puts "##"
      $stdout.puts self.description.lines.map {|i| "## " + i}.join("")
      $stdout.puts "##"
    end
  end

  def ignore?(arg)
    self.ignore.include?(arg)
  end
end

# For any given class, run it's script class method, adding a diffeq as the first parameter
def script(klass, *args, &block)
  args += process_args(klass)
  if DIFFEQ_ARGS[:describe] then
    $stdout.puts
    $stdout.puts klass.description
    $stdout.puts
    exit(1)
  end

  if $stdin.tty? then
    $stdout.puts $help unless $help.nil?
    $stdout.puts "If input is not piped in, a diffeq will be requested."
    $stdout.puts
  end

  klass.script(readDiffEq, *args, &block)
end

# Some helper methods to make code a bit nicer
class Array
  def sum(init=0)
    self.inject(init) {|sum, obj| sum + (block_given? ? yield(obj) : obj)}
  end

  def product(init=1)
    self.inject(init) {|prod, obj| prod * (block_given? ? yield(obj) : obj)}
  end

  def delete_first(obj)
    result = self.dup
    idx = result.find_index(obj)
    result.delete_at(idx) unless idx.nil?
    result
  end

  # The current array is treated as a digit string where
  # the i'th digit has radix sizes[i]; add one to the last
  # digit of self and then do any carries necessary. If
  # sizes has any negative elements or is smaller than self
  # there may be issues.
  def increment(sizes)
    self[-1] += 1
    (self.length - 1).downto(0) {|i|
      return true if sizes[i] != self[i]
      self[i] = 0
      return false if i == 0
      self[i-1] += 1
    }
    $stderr.puts("We should not be here!")
    exit(-1)
  end

  # Use self as the sizes for enumerating all the
  # digit strings from 0...0 up to self (see above)
  def enumcount
    indices = self.map { 0 }
    while true
      yield(indices)
      break unless indices.increment(self)
    end
  end
end

class Hash
  # Just like array
  def compact
    self.delete_if {|k, v| v.nil?}
  end

  alias_method :old_keys, :keys
  def keys(*args)
    return self.old_keys if args.empty?
    self.keys.select {|k| args.include?(self[k])}
  end

  def subhash(&block)
    result = self.select(&block)
    Array === result ? result.inject(Hash.new) {|h, (k, v)| h.update(k => v)} : result
  end
end

# A graph is just a hash of hashes.
#   graph[src][dst] = edgelist going from src to dst
# all we do is add inspection, as that's all that really
# matters--the hashing part is already done by ruby...
class Graph < Hash
  @@superinspect = false
  def inspect
    return super.inspect if @@superinspect
    fix = Proc.new {|arr| arr.length == 1 ? arr[0] : arr}
    result = self.keys.sort.map {|src|
      self[src].keys.sort.map {|dst|
        edges = self[src][dst]
        "(#{fix[src]} ; #{fix[dst]}): #{fix[edges]}"
      }
    }.flatten.join(", ")
    "< #{result} >"
  end
end

class Numeric
  def niceDiv(divisor)
    if self.is_a?(Integer) && divisor.is_a?(Integer) && self % divisor == 0 then
      self / divisor
    else
      self / divisor.to_f
    end
  end
end

class Integer
  # Yield all the partitions of the given integer.
  def partition
    return if self < 0
    if self == 0 then
      yield([])
      return
    end

    saw = Set.new
    (1..self).each {|i|
      (self-i).partition {|split|
        split.unshift(i)
        split.sort!

        next if saw.include?(split)
        saw << split

        yield(split)
      }
    }
  end

  # Put all the partitions in an array and return that
  def partitions
    parts = []
    self.partition {|p| parts << p }
    parts
  end

  # Change an int to y'''''...
  def to_y
    (self < 0) ? '' : ('y' + ("'" * self))
  end
end

