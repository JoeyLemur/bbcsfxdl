# Step 3 in the process:  Actually do the downloads.

# Standard libraries
require 'net/http'
require 'digest'
require 'optparse'
require 'pathname'
# 3rd-party gems
require 'sqlite3'
require 'progressbar'
require 'pp'

# Define convenience constants
KBYTE = 1024
MBYTE = KBYTE * 1024
GBYTE = MBYTE * 1024

# Pretty-print decimal numbers
# https://dzone.com/articles/format-number-thousands
def commas(number)
  return sprintf("%d", number).gsub(/(\d)(?=\d{3}+$)/, '\1,')
end

# Set up option parsing
Options = Struct.new(:rate,:limit,:dlpath,:sizeReverse)
class Parser
  def self.parse(options)
    args = Options.new("world")

    # Defaults
    args.rate = 256 * KBYTE
    args.limit = 20 * GBYTE
    args.sizeReverse = false

    optParser = OptionParser.new do |opts|
      opts.banner = "Usage: #{$0}"

      opts.on("-r","--rate KBYTESEC","Limit download rate to specified kbytes/sec (default 256)") do |n|
        args.rate = n.to_i * KBYTE
        if args.rate <= 0 then
          STDERR.puts "Rate limit must be a non-zero value!"
          Kernel.exit(1)
        end
      end
  
      opts.on("-l","--limit GBYTES","Limit download to specified gbytes of data (default 20)") do |n|
        args.limit = n.to_i * GBYTE
        if args.limit <= 0 then
          STDERR.puts "Download limit must be a non-zero value!"
          Kernel.exit(1)
        end
      end
      
      opts.on("-o","--outdir PATH","Path to download directory (required)") do |n|
        dir = Pathname.new(n)
        if not dir.exist? then
          STDERR.puts "Specified output directory does not exist!"
          Kernel.exit(1)
        end
        args.dlpath = dir.realpath
      end
      
      opts.on("-s","--size","Download largest files first, instead of smallest") do |n|
        args.sizeReverse = true
      end
      
      opts.on("-h","--help","Prints this help") do
        puts opts
        Kernel.exit(0)
      end
    end
    optParser.parse!(options)
    return args
  end
end
options = Parser.parse(ARGV)

# Check to make sure we have an output directory
if options.dlpath.nil? then
  STDERR.puts "Output directory not specified!"
  Kernel.exit(1)
end

# Report on what options we're running with
STDERR.puts <<-EOS
Output directory: #{options.dlpath.to_s}
      Rate limit: #{(options.rate / KBYTE).to_i} kbytes/sec
  Download limit: #{(options.limit / GBYTE).to_i} gbytes
  
EOS

# Count how many bytes have been downloaded
downloaded = 0

# Open the database
# TODO: Assumes its in the same directory that you're in...
db = SQLite3::Database.open('soundfiles.db')

# Prepare the update statement
stmt = db.prepare("update soundfiles set downloaded=?, sha256=? where id=?")

# Get the list of things-to-download
sql = "select id,filename,size from soundfiles where downloaded = 0 order by size "
if options.sizeReverse then
  sql += "desc"
else
  sql += "asc"
end

rs = db.execute(sql)
rowcount = rs.size
STDERR.puts "#{Time.now} : #{rowcount} to download"
if rowcount == 0 then
  STDERR.puts "Ending run, nothing to do."
  Kernel.exit(0)
end

# Open up the http connection
http = Net::HTTP.start('bbcsfx.acropolis.org.uk',80)

# Init count of how many rows we've worked with
count = 0

# Iterate over the rows
rs.each do |row|
  # Stop if we're over the defined download-per-go byte limit
  break if downloaded >= options.limit
  # Increment row count and spit out information
  count += 1
  STDERR.puts "#{Time.now}: #{commas(count)}/#{commas(rowcount)} - #{commas(options.limit - downloaded)} bytes left - #{commas(row[0])} : #{row[1]} : #{commas(row[2])}"

  # Determine the path where to write the file
  filename = "#{options.dlpath.to_s}/#{row[1]}"

  # Set up progress bar
  bytecounter = 0
  pbar = ProgressBar.create(
  :title => row[1],
  :starting_at => 0,
  :total => row[2].to_i,
  :format => '%a %B %p%% %r KB/sec',
  :rate_scale => lambda { |rate| rate / 1024 }
  )
  # Open the output file
  File.open(filename,'wb') do |file|
    startTime = Time.now.to_f   # Get the timestamp for when we start
    # Perform the download, incrementing the progress bar as it goes
    http.get("/assets/#{row[1]}") do |data|
      # Write the received data
      file.write data
      # Increment progress bar and byte count
      bytecounter += data.length
      pbar.progress = bytecounter
      # Get the total time we've been downloading
      timeTotal = Time.now.to_f - startTime
      # Calculate average bytes per second
      rate = bytecounter / timeTotal
      # Handle if the average rate is over what we want
      if rate > options.rate then
        # How many seconds it should've taken at options.rate
        howLong = (bytecounter.to_f / options.rate)
        # Sleep for a period to maintain average rate
        sleep(howLong-timeTotal)
      end
    end # http.get
  end # File.open

  # Close out the progresss bar
  pbar.finish

  # Get the filesize of the data we wrote
  filesize = File.size(filename).to_i

  # Paranoia check -- file size should match what we expect
  if filesize != row[2].to_i then
    STDERR.puts <<-EOS
    ***ARGH ARGH ARGH***
    Filesizes not the same for #{filename}!  Deleting it.
    Expected #{row[2].to_i}, got #{filesize.to_i}
    EOS
    File.delete(filename)
    stmt.close if stmt
    db.close if db
    Kernel.exit(1)
  end

  # Hash the file
  hashdigest = Digest::SHA256.file(filename).hexdigest

  # Update database, marking it downloaded and storing the hash
  stmt.execute(1,hashdigest,row[0].to_i)

  # Add to the downloaded bytes counter
  downloaded += filesize
end

# End and cleanup
STDERR.puts "#{Time.now}: Ending run with #{commas(downloaded)} bytes downloaded, #{commas(count)} of #{commas(rowcount)} files downloaded."

stmt.close if stmt
sleep(1)  # More paranoia
db.close if stmt

