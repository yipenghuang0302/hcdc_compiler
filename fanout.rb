
require './base'
require './layout'

class Fanout
  def self.findFans(layout)
    output = layout[:state][:outputs]

    output.keys.select {|key|
      key[:type] == :var || output[key].length > 1
    }.inject(Hash.new) {|h, key|
      h.update(key => output[key])
    }
  end

  def self.calculateFans(layout)
    fanid, fanning2id, id2fanning = 0, {:var => {}, :mul => {}, :fans => {}, :add => {}}, Hash.new
    Fanout.findFans(layout).keys.each {|fanning|
      id2fanning.update(fanid => fanning)
      fanning2id[fanning[:type]][fanning[:ref]] = fanid
      fanid += 1
    }

    return [id2fanning, fanning2id]
  end

  def self.updateFanout(ref, fanout)
    return (fanout[ref[:type]].include?(ref[:ref])) ? ref.update(:type => :fan, :ref => fanout[ref[:type]][ref[:ref]]) : ref
  end

  def self.calculateFanout(layout)
    layout[:state][:fan], fanout = *self.calculateFans(layout)
pp layout[:state][:fan]

    layout[:state][:mul].values.each {|mul|
      [:left, :right].each {|sym|
        mul[sym] = Fanout.updateFanout(mul[sym], fanout)
      }
    }
    layout[:state][:add].values.each {|add|
      add[:terms].map! {|fanning| Fanout.updateFanout(fanning, fanout)}
    }

    { :node => layout[:node],
      :result => layout[:result],
      :mul => layout[:state][:mul],
      :add => layout[:state][:add],
      :fan => layout[:state][:fan],
      :outputs => layout[:state][:outputs] }
  end

  def self.script(input, quiet=false, readout)
    conn = Connections.new(input, quiet)
    p conn.instance_eval {@diffeq}
    results = conn.connect
    p results
    layout = Layout.layout(results, readout)
    pp layout
    fanout = Fanout.calculateFanout(layout)
    pp fanout
  end
end

script(Fanout, true, ARGV.shift.to_i) if __FILE__ == $0
