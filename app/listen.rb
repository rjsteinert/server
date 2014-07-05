#! /usr/bin/ruby

require 'listen'

$jsDir = File.join Dir.pwd, "_attachments", "js"

class String
  # colorization
  def colorize(color_code)
    "\e[#{color_code}m#{self}\e[0m"
  end

  def red
    colorize(31)
  end

  def green
    colorize(32)
  end

  def yellow
    colorize(33)
  end

  def pink
    colorize(35)
  end
end

def push

  # Save current version number
  version = `git log --pretty=format:'%h' -n 1`
  File.open( File.join($jsDir, "version.js"), "w") {|f| f.write("window.Tangerine.version = \"#{version}\"\;") }

  Dir.chdir( $jsDir ) {
    `./uglify.rb dev`
    puts "\nGenerated:\t\tindex-dev.html"
    `./uglify.rb version.js`
    `./uglify.rb app`
    puts "\nCompiled\t\tapp.js\n\n"
  }
  puts `couchapp push`
end

def notify( type, message )
  printf "\a"
  unless `which osascript`.empty? # on a mac?

    message = /\.coffee,(.*?)\n/.match(message)[1]
    `osascript -e 'tell app "System Events" to display dialog "#{type}\n\n#{message}"'`
  end
  unless `which notify-send`.empty? # on linux with notify-send
    `notify-send "#{type} - #{message}" -i /usr/share/icons/Humanity/status/128/dialog-warning.svg &`
  end
end

puts "\nGo ahead, programmer. I'm listening...\n\n"

listen = Listen.to(".") do |modified, added, removed|

  files = modified.concat(added).concat(removed)

  files.each { |file|
    # Handle coffeescript files
    /.*\.coffee$/.match(file) { |match|

      match = match.to_s

      localMatch = match.gsub(Dir.pwd,'')

      if match.index "translation.coffee"
        # special case for i18n translation files. We just want a basic JSON object, nothing else.
        path = match.split("/")
        puts "\nCompiling translation file for language: #{path[-2]}"
        newFile = path[0..path.length-2].join("/")+"/translation.json"
        result = `coffee --compile --bare --print #{match}`
        bareJson = result.gsub(/[\;\(\)]|\/\/.*$\n/, '')
        File.open(newFile, "w") {|f| f.write(bareJson)}
        result = "" # to pass error checking
      else
        # Otherwise, just compile
        puts "\nCompiling:\t\t#{localMatch}"
        couchSpecial = /shows\/|views\/|lists\//.match(match)
        result = `coffee --bare --compile #{match} 2>&1`
        if not couchSpecial
          jsFile = match.gsub(".coffee", ".js")
          Dir.chdir($jsDir) {
            puts `./uglify.rb #{jsFile}`
          }
        end

      end

      if result.index "error" 
        # Show errors
        notify("CoffeeScript Error", result.gsub(/.*error.*\/(.*\.coffee)/,"\\1"))
        puts "\nCoffeescript error\n******************\n#{result}".red()
      end

    } # END of coffeescripts

    # handle LESS -> CSS
    /.*\.less$/.match(file) { |match|

      localMatch = match.to_s.gsub(Dir.pwd, '')

      puts "\nCompiling:\t\t#{localMatch}"
      result = `lessc #{match} --yui-compress > #{match}.css`
      if result.index "Error"
        notify("LESS error",result)
        puts "\nLESS error\n******************\n#{result}".red()
      end
    } # END of LESS

    # Handle all the resulting compiled files
    /.*\.css|.*\.js$|.*\.html$|.*\.json$/.match(file) { |match|

      # Don't trigger push for these files
      unless /version\.js|app\.js|index-dev|\/min\/|\/spec\//.match(file)

        localMatch = match.to_s.gsub(Dir.pwd,'')

        libFile = /lib\//.match(file)
        if libFile
          puts "\nUpdating:\t\tlib.js with #{localMatch}"
          Dir.chdir($jsDir) {
            puts `./uglify.rb lib`
          }
        else
          puts "\nUpdating:\t\t#{localMatch}"
        end

        push()
      end
    } # END of compiled files

  } # END of each file

end

listen.start
sleep