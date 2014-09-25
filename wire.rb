#!/usr/bin/env ruby

require './base'
require './fanout'

module Wiring
class Connection
  attr_reader :source, :output, :destination, :input

  def initialize(src, output, dst, input)
    @source, @output = src, output
    @destination, @input = dst, input
  end

  def inspect
    "%s::%d => %s::%d" % [
      @source.inspect(true),
      @output,
      @destination.inspect(true),
      @input
    ]
  end
end

class Node
  @@fanout, @@nodes = nil, Hash.new
  def self.fanout=(fanout)
    @@fanout = fanout
    Output.new
  end

  def self.wire
    @@nodes.values.map {|node| node.wire}.flatten
  end

  # Skip additions and go straight to where the data should go.
  def self.getNode(node)
    if node[:type] == :add then
      @@fanout[:outputs][node].map {|node| self.getNode(node)}
    else
      @@nodes[node]
    end
  end

  def wire
    outputs.map {|dst| Node.getNode(dst)}.flatten.map {|dst|
      Connection.new(self, self.nextOutput, dst, dst.nextInput)
    }
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

    @@nodes[hkey] = self
    @index, @key, @data, @outputs = index + 1, hkey, data, outputs
    @column, @row = ['col', @type, col].compact.join('_'), "row_#{row}"
    @input, @output = 0, 0
  end

  def inspect(short=false)
    if short then
      "(<@{type}[#{@index}]:#{@row},#{@column}>)"
    else
      [ "{==",
        "  #{@type}[#{@index}] at (#{@row}, #{@column})",
        "  #{@key.inspect} yielding #{@data.inspect}",
        "  #> #{@outputs.inspect}",
        "==}" ].join("\n")
    end
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

## Must come last.
class Output < Node
  @@count = 0
  def initialize
    raise "Output generated twice" if @@count > 0
    super(@@count, 0)
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
    [:var, :mul, :fan].each {|node|
      fanout[node].keys.sort.each {|key|
        byclass[node].new(key)
      }
    }

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