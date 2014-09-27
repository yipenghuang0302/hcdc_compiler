#!/usr/bin/env ruby

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

# For any given class, run it's script class method, adding a diffeq as the first parameter
def script(klass, *args, &block)
  if $stdin.tty? then
    klass.usage
    $stdout.puts
  end
  klass.script(readDiffEq, *args, &block)
end

class Object
  def base_class_name
    self.class.to_s.split(/::/)[-1]
  end
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

