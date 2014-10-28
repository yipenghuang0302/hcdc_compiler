#!/usr/bin/env ruby

require './base'
require './layout'
## See description method below for info.

class Fanout
  def self.calculateFans(layout)
    fanid, fans = 0, layout[:state][:outputs].select {|key, value| value.length > 1}
    fanning2id, id2fanning = {:var => {}, :mul => {}, :fans => {}, :add => {}}, Hash.new

    fans.keys.sort_by {|fanning| [fanning[:type].to_s, fanning[:ref]]}.each {|fanning|
      id2fanning.update(fanid => fanning)
      fanning2id[fanning[:type]][fanning[:ref]] = fanid
      fanid += 1
    }

    return [id2fanning, fanning2id]
  end

  def self.updateToFan(key, fanout)
    type, ref = key[:type], key[:ref]
    return fanout[type].include?(ref) ? { :type => :fan, :ref => fanout[type][ref] } : key
  end

  def self.basicFanout(layout, *readouts)
    output_ref = 0

    readouts.each {|readout|
      next if readout == layout[:result]
      # The given variable is guaranteed to have an output either to another
      # integrator or if it is order 0 to the overall equation (as otherwise
      # a change of variable could easily reduce the order)
      layout[:state][:outputs][{:type => :var, :ref => readout}] << {:type => :output, :ref => output_ref}
      output_ref += 1
    }
    layout[:state][:fan], fanout = *self.calculateFans(layout)

    ## Put the fan in between input and output -- i.e. make it a fan
    layout[:state][:fan].keys.each {|fan|
      fanning = layout[:state][:fan][fan]
      result = layout[:state][:outputs][fanning]
      fanref = {:type => :fan, :ref => fan}

      layout[:state][:outputs][fanref] = result
      layout[:state][:outputs][fanning] = [fanref]
    }

    ## Fanout, a hash from fanning (what needs to fan) to fan id
    layout[:state][:mul].values.each {|mul|
      [:left, :right].each {|sym|
        mul[sym] = Fanout.updateToFan(mul[sym], fanout)
      }
    }
    layout[:state][:add].values.each {|add|
      add[:terms].map! {|fanning| Fanout.updateToFan(fanning, fanout)}
    }

    node = layout[:node]
    if readouts.include?(layout[:result]) then
      # Add a fan for the final node to feed into and then fan this result
      # to the output and into the first integrator
      fanid = (layout[:state][:fan].keys.max || -1) + 1
      feeder = {:type => :fan, :ref => fanid}
      int = {:type => :var, :ref => layout[:result] - 1}

      ## Update the node to go to this.
      layout[:state][:outputs][node].map! {|item| item == int ? feeder : item}
      layout[:state][:outputs][feeder] = [int, {:type => :output, :ref => output_ref}]
      layout[:state][:fan][fanid] = node

      output_ref += 1
      node = feeder
    end

    # The output node has no outputs. Just a good idea.
    (0...output_ref).each {|output|
      layout[:state][:outputs][{:type => :output, :ref => output}] = []
    }

    { :node => node,
      :result => layout[:result],
      :mul => layout[:state][:mul],
      :add => layout[:state][:add],
      :fan => layout[:state][:fan],
      :outputs => layout[:state][:outputs] }
  end

  def self.usage
    puts "ruby fanout.rb output+"
    puts "\tArguments are up to four orders to output"
    puts "\t-- order 0 is y, order 1 is y', can go up to the LHS of the equation"
    puts "\t-- outputs are uniqued and sorted"
    puts "\tIf input is not piped in, a diffeq will be requested"
  end

  def self.description
    puts <<-END_DESCRIPTION
## fanout.rb:
##
## This file will acquire the layout information for a differential equation
## using layout.rb. The resulting information is then transformed to make use
## of `fan' nodes, which are the only nodes that can genuinely have more than
## a single output. The output of this file is a hash containing:
##   1) A reference to the root node (i.e. the node that should feedback into
##      the high order term that is the result of the equation). The node is
##      of the form {:type => type, :ref => ID} where type is either :mul,
##      :add, :var, or :fan and ID is which mul, add, var, or fan it is.
##   2) The order of the result
##   3) A hash going from Multiplication Node ID to factors where the key
##      is the ID (integer), the value for a given key is a hash with two
##      values, :left and :right. Both point to hashes that have the same
##      form--a value key :type whose value denotes what the type of the
##      factor is (:mul, :var, :add, :fan, etc) followed by the ID of the
##      value (i.e. which add, which mul, or what order variable).
##   4) Similar to the above, a hash mapping add ID's (integers) to a hash
##      containing only one key, :terms, which maps to a list of values of
##      the form {:type => sym, :ref => ID} where sym is :mul, :add, :fan,
##      or :var and ID is the identifier for a value of the given type
##   5) In the same vein as above, but now a hash mapping fan nodes (keyed
##      by ID) to a hash mapping the fan's output to a given node. outputs
##      are indexed by integers starting at 0.
##   6) A hash where each key is of the form {:type => sym, :ref => ID}
##      and the values are lists of `nodes' of the same form that the
##      given keyed node will output to (i.e. everything needing it).
##
## An additional note is that if readouts are given, then connections will
## be added to the given output from the given variable value. The outputs
## will be directed to nodes of the form {:type => :output, :ref => ID} for
## a given output and the output of such a node is []
##
    END_DESCRIPTION
  end

  def self.script(input)
    layout = Layout.script(input)
    readouts = DIFFEQ_ARGS[:readouts].select {|i|
      i.between?(0, layout[:result])
    }
    fanout = Fanout.basicFanout(layout, *readouts)

    self.describe
    puts "<fanout>"
    pp fanout
    puts "</fanout>"

    return fanout
  end
end

script(Fanout) if __FILE__ == $0
