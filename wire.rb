#!/usr/bin/env ruby

require './base'
require './fanout'

module Wiring
class Node
  @@fanout, @@nodes, @@index = nil
  def self.fanout=(fanout)
    @@fanout = fanout
  end

  def self.nodes=(array)
    @@nodes = array
    @@index = array.inject({:index => 0}) {|h, node|
      h.update(node.key => h[:index], :index => h[:index] + 1)
    }
    @@index.delete(:index)

    @@nodes
  end

  def self.wire
    @@nodes.map {|node| node.wire}.flatten
  end

  def wire
    nil
  end

  attr_reader :column, :row, :type, :index, :key, :data, :outputs

  def initialize(index, key)
    single = self.is_a?(Int)

    col = single ? nil : (index % 2 == 0 ? 'l' : 'r')
    row = index/(single ? 1 : 2) + 1

    @type = self.class.to_s.downcase.split(/::/)[-1]
    sym = (@type == 'int') ? :var : @type.intern

    hkey = {:type => sym, :ref => key}
    data = @@fanout[sym][key]
    outputs = @@fanout[:outputs][hkey]

    @index, @key, @data, @outputs = index + 1, hkey, data, outputs
    @column, @row = ['col', @type, col].compact.join('_'), "row_#{row}"
    @input, @output = 0, 0
  end

  def inspect
    [ "{==",
      "  #{@type}[#{@index}] at (#{@row}, #{@column})",
      "  #{@key.inspect} yielding #{@data.inspect}",
      "  #> #{@outputs.inspect}",
      "==}" ].join("\n")
  end

  def nextInput
    @input += 1
  end

  def nextOutput
    @output += 1
  end
end

class Mul < Node
  @@count = 0

  def initialize(key)
    super(@@count, key)
    @@count += 1
  end

  def self.count
    @@count
  end
end

class Fan < Node
  @@count = 0

  def initialize(key)
    super(@@count, key)
    @@count += 1
  end

  def self.count
    @@count
  end
end

class Int < Node
  @@count = 0

  def initialize(key)
    super(@@count, key)
    @@count += 1
  end

  def self.count
    @@count
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

  def self.generate(fanout)
    fanout[:var] = Hash.new
    0.upto(fanout[:result] - 1) {|order| fanout[:var][order] = {:type => :var, :ref => order}} 

    byclass = {:var => Wiring::Int, :mul => Wiring::Mul, :fan => Wiring::Fan}
    Wiring::Node.fanout = fanout
    Wiring::Node.nodes = [:var, :mul, :fan].map {|node|
      fanout[node].keys.sort.map {|key|
        byclass[node].new(key)
      }
    }.flatten

    error("Not enough integrators to solve #{integrators} order equation!") if Wiring::Int.count > @@nums[:ints]
    error("Not enough multipliers available!") if Wiring::Mul.count > @@nums[:muls]
    error("Not enough fanouts available!") if Wiring::Fan.count > @@nums[:fans]
    ## Wirings merely connect outputs to inputs (i.e. it goes `forward')

    Wiring::Node.wire
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