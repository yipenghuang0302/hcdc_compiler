#!/usr/bin/env ruby

require './base'
require './fanout'

module Wiring
class Connection
  @@count = 0
  attr_reader :source, :output, :destination, :input

  def initialize(src, output, dst, input)
    @connID = @@count
    @@count += 1

    @source, @output = src, output
    @destination, @input = dst, input
  end

  def inspect
    "Connection %d:\t%s::%d => %s::%d" % [
      @connID,
      @source,
      @output,
      @destination,
      @input
    ]
  end
  def to_s
    inspect
  end
end

class Node
  @@fanout, @@nodes = nil, Hash.new
  def self.fanout=(fanout)
    @@fanout = fanout
    Output.new(0)
  end

  # We need to start from the root and go there.
  def self.wire
    # Make all the addition wires
    fromKeys = Proc.new {|keys| keys.map {|key| @@nodes[key]}}
    additions = @@nodes.values.select {|node| node.key[:type] == :add}.map {|add|
      terms = fromKeys[add.data[:terms]]
      fromKeys[add.outputs].map {|output|
        input = output.nextInput
        terms.map {|src|
          Connection.new(src, src.nextOutput, output, input)
        }
      }
    }.flatten

    # Now we just connect everything else EXCEPT additions
    irregular = Proc.new {|node| [:output, :add].include?(node.key[:type])}
    rest = @@nodes.values.reject(&irregular).map {|src|
      fromKeys[src.outputs].reject(&irregular).map {|dst|
        Connection.new(src, src.nextOutput, dst, dst.nextInput)
      }
    }.flatten

    additions + rest
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

  def to_s
    "(<@{type}[#{@index}]:#{@row},#{@column}>)"
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

Mul, Fan, Int, Add, Output = *(1..5).map {
  Class.new(Node) do
    self.class_variable_set("@@count", 0)
    def initialize(key)
      count = self.class.class_variable_get("@@count")
      raise "Output generated twice" if self.is_a?(Output) && count > 0
      super(count, key)
      self.class.class_variable_set("@@count", count + 1)
    end

    def self.count
      self.class_variable_get("@@count")
    end
  end
}
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

    byclass = {:var => Wiring::Int, :mul => Wiring::Mul, :fan => Wiring::Fan, :add => Wiring::Add}
    Wiring::Node.fanout = fanout
    [:var, :mul, :fan, :add].each {|node|
      fanout[node].keys.sort.each {|key|
        byclass[node].new(key)
      }
    }

    error("Not enough integrators to solve #{fanout[:result]} order equation!", -1) if Wiring::Int.count > @@nums[:ints]
    error("Not enough multipliers available!", -1) if Wiring::Mul.count > @@nums[:muls]
    error("Not enough fanouts available!", -1) if Wiring::Fan.count > @@nums[:fans]
    ## Wirings merely connect outputs to inputs (i.e. it goes `forward')

    Wiring::Node.wire
  end

  def self.script(input, quiet=false, readout)
    wiring = Wire.generate(Fanout.script(input, quiet, readout))
    puts "<wiring>"
    wiring.each {|wire| puts "  - #{wire}"}
    puts "</wiring>"
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