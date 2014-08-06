#!/usr/bin/env ruby

require 'set'
require 'open3'

class Integer
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

  def partitions
    parts = []
    self.partition {|p| parts << p }
    parts
  end

  def to_y
    if self < 1 then
      $stderr.puts "Cannot change #{self} to_y, not big enough!"
      exit(-1)
    end

    return 'y' + ("'" * (self - 1))
  end
end

class String
  def order
    return self.scan(/'+/).map {|i| i.length}.max || 0
  end

  def incOrder(amt=1)
    return amt <= 0 ? self : self.gsub(/y/, (amt+1).to_y)
  end

  def randomCoefs
    # Just use some random coefficients between -20 and 20
    coefs = (-20..20).to_a
    return self.gsub(/y/) { "#{coefs.sample}y" }
  end
end

class Array
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

  def enumcount
    indices = self.map { 0 }
    while true
      yield(indices)
      break unless indices.increment(self)
    end
  end

  def diffeqs
    splits = self.map {|i| i.partitions}
    splits.map {|arr| arr.length}.enumcount {|indices|
      orders = splits.zip(indices).map {|arr, i| arr[i]}
      yield(orders.map {|term|
        term.map {|factor| factor.to_y }
      }.join(" + "))
    }
  end
end

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

def runDiffeq(diffeq)
  generateDiffeqs(diffeq) {|eq|
    $stdout.puts ">>> #{eq} <<<"
    Open3.popen3("ruby", "diffeq.rb") {|stdin, stdout, stderr, wait_thr|
      stdin.puts(eq)
      stdin.close
      $stdout.puts stdout.readlines
      exit_status = wait_thr.value
      $stderr.puts "Error on #{eq}" if exit_status.to_i != 0
    }
  }
end

def constants
  return [0, 1, 2]
end

def termshifts
  return [0, 1, 2]
end

def eqshifts
  return [0, 1, 2]
end



args = ARGV.map {|i| i.to_i}

args.each {|arg|
  $stdout.puts
  $stdout.puts ">>> !! arg = #{arg} !! <<<"
  $stderr.puts "Checking arg #{arg}"
  arg.partition {|arr|
    arr.diffeqs {|diffeq|
      runDiffeq(diffeq)
    }
  }
}
