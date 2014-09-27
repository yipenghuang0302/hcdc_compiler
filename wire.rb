#!/usr/bin/env ruby

require './base'
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

  attr_reader :index, :key, :data, :outputs

  def initialize(index, key)
    sym = self.is_a?(Int) ? :var : self.class.to_s.downcase.split(/::/)[-1].intern

    hkey = {:type => sym, :ref => key}
    data = @@fanout[sym][key]
    outputs = @@fanout[:outputs][hkey]

    @@nodes[hkey] = self
    @index, @key, @data, @outputs = index, hkey, data, outputs
    @input, @output = 0, 0
  end

  def to_s
    "(<#{self.base_class_name}:#{@index}>)"
  end

  def inspect
    "(<#{self.base_class_name}:#{@index} -- #{@key.inspect} => #{@data.inspect} #> #{@outputs.inspect}>)"
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

Mul, Fan, Int, Add, Output = *(1..5).map {
  Class.new(Node) do
    self.class_variable_set("@@count", 0)
    def initialize(key)
      count = self.class.class_variable_get("@@count")
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
    :fans => 8,
    :outs => 4
  }

  def self.generate(fanout)
    fanout[:var] = Hash.new
    0.upto(fanout[:result] - 1) {|order| fanout[:var][order] = {:type => :var, :ref => order}} 

    byclass = {:var => Wiring::Int, :mul => Wiring::Mul, :fan => Wiring::Fan, :add => Wiring::Add, :output => Wiring::Output}
    Wiring::Node.fanout = fanout
    [:var, :mul, :fan, :add, :output].each {|node|
      fanout[node].keys.sort.each {|key|
        byclass[node].new(key)
      }
    }

    error("Not enough integrators to solve #{fanout[:result]} order equation!", -1) if Wiring::Int.count > @@nums[:ints]
    error("Not enough multipliers available!", -1) if Wiring::Mul.count > @@nums[:muls]
    error("Not enough fanouts available!", -1) if Wiring::Fan.count > @@nums[:fans]
    error("Not enough outputs available!", -1) if Wiring::Output.count > @@nums[:outs]
    ## Wirings merely connect outputs to inputs (i.e. it goes `forward')

    Wiring::Node.wire
  end

  def self.usage
    puts "ruby wire.rb output+"
    puts "\tArguments are up to four orders to output"
    puts "\t-- order 0 is y, order 1 is y', can go up to the LHS of the equation"
    puts "\t-- outputs are uniqued and sorted"
    puts "\tIf input is not piped in, a diffeq will be requested"
  end

  def self.script(input, quiet=false, kfan=3, readouts)
    wiring = Wire.generate(KFans.script(input, quiet, kfan, readouts))
    puts "<wiring>"
    wiring.each {|wire| puts "  - #{wire}"}
    puts "</wiring>"
    wiring
  end
end


script(Wire, true, 3, ARGV) if __FILE__ == $0
