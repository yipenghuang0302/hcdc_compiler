
require './base'
require './layout'

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

  def self.updateFanout(ref, fanout)
    return (fanout[ref[:type]].include?(ref[:ref])) ? ref.update(:type => :fan, :ref => fanout[ref[:type]][ref[:ref]]) : ref
  end

  def self.calculateFanout(layout, *readouts)
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

    layout[:state][:fan].keys.each {|fan|
      fanning = layout[:state][:fan][fan]
      result = layout[:state][:outputs][fanning]
      fanref = {:type => :fan, :ref => fan}

      layout[:state][:outputs][fanref] = result
      layout[:state][:outputs][fanning] = [fanref]
    }

    layout[:state][:mul].values.each {|mul|
      [:left, :right].each {|sym|
        mul[sym] = Fanout.updateFanout(mul[sym], fanout)
      }
    }
    layout[:state][:add].values.each {|add|
      add[:terms].map! {|fanning| Fanout.updateFanout(fanning, fanout)}
    }

    node = layout[:node]
    if readouts.include?(layout[:result]) then
      # Add a fan for the final node to feed into and then fan this result
      # to the output and into the first integrator
      feeder = {:type => :fan, :ref => layout[:state][:fan].keys.max + 1}
      int = {:type => :var, :ref => layout[:result] - 1}

      ## Update the node to go to this.
      layout[:state][:outputs][node].map! {|item| item == int ? feeder : item}
      layout[:state][:outputs][feeder] = [int, {:type => :output, :ref => output_ref}]
      layout[:state][:fan][2] = node

      output_ref += 1
      node = feeder
    end

    # The output node has no outputs. Just a good idea.
    (0...output_ref).each {|output|
      layout[:state][:outputs][output] = []
    }

    { :node => node,
      :result => layout[:result],
      :mul => layout[:state][:mul],
      :add => layout[:state][:add],
      :fan => layout[:state][:fan],
      :output => Hash.new, # So that we can index by the output node
      :outputs => layout[:state][:outputs] }
  end

  def self.usage
    puts "ruby fanout.rb output+"
    puts "\tArguments are up to four orders to output"
    puts "\t-- order 0 is y, order 1 is y', can go up to the LHS of the equation"
    puts "\t-- outputs are uniqued and sorted"
    puts "\tIf input is not piped in, a diffeq will be requested"
  end

  def self.script(input, quiet=false, *readouts)
    layout = Layout.script(input, quiet)
    readouts = readouts.flatten.map {|i| i.to_i}.select {|i|
      i.between?(0, layout[:result])
    }.uniq.sort
    fanout = Fanout.calculateFanout(layout, *readouts)
    puts "<fanout>"
    pp fanout
    puts "</fanout>"

    return fanout
  end
end

script(Fanout, true, ARGV) if __FILE__ == $0
