#!/usr/bin/env ruby

require 'set'

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
end

class Array
  def diffeqs
    p self
  end
end


ARGV[0].to_i.partition {|arr|
  arr.diffeqs
}
