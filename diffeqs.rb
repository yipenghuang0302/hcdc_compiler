#!/usr/bin/env ruby

require 'set'
require 'open3'

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

  # Turn the integer into y''..''
  def to_y
    if self < 1 then
      $stderr.puts "Cannot change #{self} to_y, not big enough!"
      exit(-1)
    end

    return 'y' + ("'" * (self - 1))
  end
end

class String
  # Figure out how many orders down this y''...'' is
  def order
    return self.scan(/'+/).map {|i| i.length}.max || 0
  end

  # Increase the order of every y in this string by amt
  def incOrder(amt=1)
    return amt <= 0 ? self : self.gsub(/y/, (amt+1).to_y)
  end


  # Given the string, add random coefs from -20 to 20 to each term
  def randomCoefs
    coefs = (-20..20).to_a
    return self.gsub(/y/) { "#{coefs.sample}y" }
  end
end

class Array
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

  # We start as an array of integers; each value represents
  # the total order of a term (y counts as 1, y' is 2, yy is 2,
  # yy' is 3, yyy is 3, etc). We then take that total order
  # for each term and split it up into factors and put them all
  # together -- but we enumerate all the different possible
  # factor combinations for each term (see enumcount).
  def diffeqs
    # Get all the different ways to split each term into factors
    splits = self.map {|i| i.partitions}

    # enumerate ways to index into the partitions
    splits.map {|arr| arr.length}.enumcount {|indices|
      # Pick a partition for each term...
      orders = splits.zip(indices).map {|arr, i| arr[i]}
      # map each term (a partition) to y's and primes
      yield(orders.map {|term|
        term.map {|factor| factor.to_y }
      }.join(" + "))
    }
  end
end

# From a base expression generate various equations.
def generateDiffeqs(diffeq)
  order = diffeq.order
  termshifts.each {|tshift|
    term = (order + tshift + 2).to_y
    constants.each {|const|
      eqshifts.each {|shift|
        eq = "#{term} = #{diffeq} + #{const}".incOrder(shift)
        yield eq
        yield eq.randomCoefs
      }
    }
  }
end

# Run the given script with the given diffeq
def runDiffeq(diffeq, script)
  generateDiffeqs(diffeq) {|eq|
    $stdout.puts ">>> #{eq} <<<"
    Open3.popen3("ruby", script) {|stdin, stdout, stderr, wait_thr|
      stdin.puts(eq)
      stdin.close
      $stdout.puts stdout.readlines
      exit_status = wait_thr.value
      $stderr.puts "Error on #{eq}" if exit_status.to_i != 0
    }
  }
end

# Different constants to consider.
def constants
  return [0, 1, 2]
end

# Change each leading term by this amount (add primes)
def termshifts
  return [0, 1, 2]
end

# Change all the y's in the equation by these amounts
def eqshifts
  return [0, 1, 2]
end



script = "diffeq.rb"
ARGV.map {|arg|
  case arg
    when "-d"
      script = "diffeq.rb"
      nil
    when "-l"
      script = "layout.rb"
      nil
    when /^\d+$/
      arg.to_i
    else
      $stderr.puts "Error in arguments for tester!"
      exit(1)
  end
}.compact.each {|arg|
  $stdout.puts
  $stdout.puts ">>> !! arg = #{arg} !! <<<"
  $stderr.puts "Checking arg #{arg}"
  arg.partition {|arr|
    arr.diffeqs {|diffeq|
      runDiffeq(diffeq, script)
    }
  }
}
