
require './base'
require './wire'

module Wiring
class Connection
  def c_code
<<-C_CODE
conn conn_#{@connID} = {
  #{@source.row}, #{@source.column}, out_#{@output-1}, #{@destination.row}, #{@destination.column}, in_#{@input}
};
set_conn (conn_#{@connID});
C_CODE
  end
end
end

class CodeGen
  def self.script(input, quiet=false, readout=0, file=nil)
    connections = Wire.script(input, quiet, readout)
    begin
      unless file.nil? then
        error("C file must have valid extension", -1) unless file =~ /\.(c|h)(pp)?$/
        File.open(file, File::WRONLY | File::CREAT | File::TRUNC) {|fout|
          connections.each {|conn|
            fout.puts conn.c_code
            fout.puts
          }
        }
      end
    rescue Exception => e
      error("Error working with the given file #{file}:\n\t#{e.message}", -1)
    end
    connections.each {|conn|
      puts conn.c_code
      puts
    }
  end
end

script(CodeGen, true, ARGV.shift.to_i, ARGV.shift) if __FILE__ == $0
