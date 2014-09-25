
require './base'
require './layout'

class Fanout
  def self.calculateFans(layout, readout)
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

  def self.calculateFanout(layout, readout)
    output = {:type => :output, :ref => 0}
    if readout != layout[:result] then
      # The given variable is guaranteed to have an output either to another
      # integrator or if it is order 0 to the overall equation (as otherwise
      # a change of variable could easily reduce the order)
      layout[:state][:outputs][{:type => :var, :ref => readout}] << output
    end
    layout[:state][:fan], fanout = *self.calculateFans(layout, readout)

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
    if readout == layout[:result] then
      # Add a fan for the final node to feed into and then fan this result
      # to the output and into the first integrator
      feeder = {:type => :fan, :ref => layout[:state][:fan].keys.max + 1}
      int = {:type => :var, :ref => layout[:result] - 1}

      ## Update the node to go to this.
      layout[:state][:outputs][node].map! {|item| item == int ? feeder : item}
      layout[:state][:outputs][feeder] = [int, output]
      layout[:state][:fan][2] = node
      node = feeder
    end

    { :node => node,
      :result => layout[:result],
      :mul => layout[:state][:mul],
      :add => layout[:state][:add],
      :fan => layout[:state][:fan],
      :outputs => layout[:state][:outputs] }
  end

  def self.script(input, quiet=false, readout)
    fanout = Fanout.calculateFanout(Layout.script(input, quiet), readout)
    puts "<fanout>"
    pp fanout
    puts "</fanout>"

    return fanout
  end
end

script(Fanout, true, ARGV.shift.to_i) if __FILE__ == $0
