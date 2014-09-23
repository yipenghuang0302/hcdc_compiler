#!/usr/bin/env ruby

require './base'
require './fanout'

module Wiring
class Node
  @@connID = 0
  attr_reader :connection, :column, :row

  def initialize(index, single=false)
    col = single ? nil : (index % 2 == 0 ? 'l' : 'r')
    row = index/(single ? 1 : 2) + 1

    @connection = @@connID
    @column = ['col', getType, col].compact.join('_')
    @row =  "row_{row}"
    @inputs = Hash.new

    @@connID += 1
  end

  def getType
    raise "getType unimplemented"
  end

  def input=(node)
    num = @input.size
    @input[node] = num
    self
  end

  def input(node)
    @input[node]
  end
end

class Mul < Node
  @@count = 0

  def initialize
    super(@@count)
    @@count += 1
  end

  def self.count
    @@count
  end

  def getType
    "mul"
  end
end

class Fan < Node
  @@count = 0

  def initialize
    super(@@count)
    @@count += 1
  end

  def self.count
    @@count
  end

  def getType
    "fan"
  end
end

class Int < Node
  @@count = 0

  def initialize
    super(@@count, true)
    @@count += 1
  end

  def self.count
    @@count
  end

  def getType
    "int"
  end
end
end

# Wire as a verb :-)
class Wire
  @@nums = {
    :ints => 4,
    :muls => 8,
    :fans => 8
  }

  @@muls, @@fans, @@ints = Hash.new, Hash.new, Hash.new

  def self.generate(fanout)
    fanout[:var] = Hash.new
    0.upto(fanout[:result] - 1) {|order| fanout[:var][order] = {:type => :var, :ref => order}} 

    byclass = {:var => Wiring::Int, :mul => Wiring::Mul, :fan => Wiring::Fan}
    byhash = {:var => @@ints, :mul => @@muls, :fan => @@fans}

    [:var, :mul, :fan].each {|node|
      fanout[node].keys.sort.each {|key|
        byhash[node][key] = byclass[node].new
      }
    }

    error("Not enough integrators to solve #{integrators} order equation!") if Wiring::Int.count > @@nums[:ints]
    error("Not enough multipliers available!") if Wiring::Mul.count > @@nums[:muls]
    error("Not enough fanouts available!") if Wiring::Fan.count > @@nums[:fans]
    ## Wirings merely connect outputs to inputs (i.e. it goes `forward')

    nil
  end

  def self.script(input, quiet=false, readout)
    wiring = Wire.generate(Fanout.script(input, quiet, readout))
    pp wiring
  end
end


script(Wire, true, ARGV.shift.to_i) if __FILE__ == $0

=begin
{:node=>{:type=>:add, :ref=>0},
 :result=>2,
 :mul=>{},
 :add=>{0=>{:terms=>[{:type=>:var, :ref=>0}, {:type=>:fan, :ref=>0}]}},
 :fan=>{0=>{:type=>:var, :ref=>1}},
 :outputs=>
  {{:type=>:var, :ref=>0}=>[{:type=>:add, :ref=>0}],
   {:type=>:var, :ref=>1}=>[{:type=>:fan, :ref=>0}],
   {:type=>:fan, :ref=>0}=>
    [{:type=>:add, :ref=>0},
     {:type=>:output, :ref=>0},
     {:type=>:var, :ref=>0}]}}
=end