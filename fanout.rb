
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

  def self.script(input, quiet=false, *readouts)
    layout = Layout.script(input, quiet)
    readouts = readouts.flatten.map {|i| i.to_i}.select {|i|
      i.between?(0, layout[:result])
    }.uniq.sort
    fanout = Fanout.basicFanout(layout, *readouts)
    puts "<fanout>"
    pp fanout
    puts "</fanout>"

    return fanout
  end
end

script(Fanout, true, ARGV) if __FILE__ == $0
