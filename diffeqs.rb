#!/usr/bin/env ruby

require 'set'
require 'open3'

require './base'

class String
  # Figure out how many orders down this y''...'' is
  def order
    return self.scan(/'+/).map {|i| i.length}.max || 0
  end

  # Increase the order of every y in this string by amt
  def incOrder(amt=1)
    return amt <= 0 ? self : self.gsub(/y/, amt.to_y)
  end


  # Given the string, add random coefs from -20 to 20 to each term
  def randomCoefs
    coefs = (-20..20).to_a
    return self.gsub(/y/) { "#{coefs.sample}y" }
  end
end

class Array
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
        term.map {|factor| (factor-1).to_y }
      }.join(" + "))
    }
  end
end

# From a base expression generate various equations.
def generateDiffeqs(diffeq)
  order = diffeq.order
  termshifts.each {|tshift|
    term = (order + tshift + 1).to_y
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
