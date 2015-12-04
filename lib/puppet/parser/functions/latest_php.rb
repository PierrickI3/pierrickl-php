#
# Gets the zip filename of a php major version
#
# Usage: latest_php()
#
require 'net/http'

module Puppet::Parser::Functions
  newfunction(:latest_php, :type => :rvalue) do |args|
    uri = URI('http://windows.php.net/downloads/releases/')
    allversions = Net::HTTP.get(uri)
    /php-5.6.\d*-nts.Win32-VC11-x64.zip/.match(allversions)
  end
end
