#!/usr/bin/env ruby

class Integer
  def partition
    return if self < 0
    if self == 0 then
      yield([])
      return
    end
      

    (1..self).each {|i|
      (self-i).partition {|split|
        split.unshift(i)
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
