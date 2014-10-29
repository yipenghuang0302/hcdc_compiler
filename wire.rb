#!/usr/bin/env ruby

require './kfans'

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
    irregular = Proc.new {|node| node.key[:type] == :add}
    rest = @@nodes.values.reject(&irregular).map {|src|
      fromKeys[src.outputs].reject(&irregular).map {|dst|
        Connection.new(src, src.nextOutput, dst, dst.nextInput)
      }
    }.flatten

    additions + rest
  end

  attr_reader :index, :key, :data, :outputs, :type
  @@count = {
    :int => 0,
    :mul => 0,
    :add => 0,
    :fan => 0,
    :output => 0
  }
  def self.count(type)
    @@count[type]
  end

  def initialize(type, key)
    sym = type == :var ? :int : type
    index = @@count[sym]
    @@count[sym] += 1

    hkey = {:type => type, :ref => key}
    data = @@fanout[type][key]
    outputs = @@fanout[:outputs][hkey]

    @@nodes[hkey] = self
    @index, @key, @data, @outputs = index, hkey, data, outputs
    @input, @output = 0, 0
    @type = sym
  end

  def to_s
    "(<#{@type.to_s}:#{@index}>)"
  end

  def inspect
    "(<#{@type.to_s}:#{@index} -- #{@key.inspect} => #{@data.inspect} #> #{@outputs.inspect}>)"
  end

  def nextInput
    result = @input
    @input += 1
    result
  end

  def nextOutput
    result = @output
    @output += 1
    result
  end
end
end

# Wire as a verb :-)
class Wire
  @@nums = {
    :ints => 4,
    :muls => 8,
    :fans => 8,
    :outs => 4
  }

  def self.generate(fanout)
    fanout[:var] = Hash.new
    0.upto(fanout[:result] - 1) {|order| fanout[:var][order] = {:type => :var, :ref => order}} 

    Wiring::Node.fanout = fanout
    [:var, :mul, :fan, :add, :output].each {|node|
      fanout[node].keys.sort.each {|key|
        Wiring::Node.new(node, key)
      }
    }

    error("Not enough integrators to solve #{fanout[:result]} order equation!", -1) if Wiring::Node.count(:int) > @@nums[:ints]
    error("Not enough multipliers available!", -1) if Wiring::Node.count(:mul) > @@nums[:muls]
    error("Not enough fanouts available!", -1) if Wiring::Node.count(:fan) > @@nums[:fans]
    error("Not enough outputs available!", -1) if Wiring::Node.count(:output) > @@nums[:outs]
    ## Wirings merely connect outputs to inputs (i.e. it goes `forward')

    Wiring::Node.wire
  end

  def self.source
    "wire.rb"
  end

  def self.description
    <<-END_DESCRIPTION
This file prints a detailed description of all the wires that would be
needed to solve the given differential equation, based off the results
from running KFans on the input equation
    END_DESCRIPTION
  end

  def self.ignore
    KFans.ignore
  end

  def self.script(input)
    wiring = Wire.generate(KFans.script(input))
    self.describe
    puts "<wiring>"
    wiring.each {|wire| puts "  - #{wire}"}
    puts "</wiring>"
    wiring
  end
end

script(Wire) if __FILE__ == $0
