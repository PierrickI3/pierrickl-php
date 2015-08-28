# == Define: php::unzip
#
# Extracts a ZIP archive on a Windows system.
#
# === Parameters
#
# [*destination*]
#  Required, the destination directory to extract the files into.
#
# [*creates*]
#  The `creates` parameter for the exec resource that extracts the ZIP file,
#  default is undefined.
#
# [*refreshonly*]
#  The `refreshonly` parameter for the exec resource that extracts the ZIP file,
#  defaults to false.
#
# [*unless*]
#  The `unless` parameter for the exec resource that extracts the ZIP file,
#  default is undefined.
#
# [*zipfile*]
#  The path to the ZIP file to extract, defaults the name of the resource.
#
# [*provider*]
#  Advanced parameter, sets the provider for the exec resource that extracts
#  the ZIP file, defaults to 'powershell'.
#
# [*options*]
#  Advanced parameter, sets the extraction options for the `Folder.CopyHere`
#  method:
#
#  http://msdn.microsoft.com/en-us/library/windows/desktop/bb787866.
#
#  Defaults to 20, which is sum of:
#   * 4:  Do not display a progress dialog box.
#   * 16: Respond with "Yes to All" for any dialog box that is displayed.
#
# [*command_template*]
#  Advanced paramter for generating PowerShell that extracts the ZIP file,
#  defaults to 'windows/unzip.ps1.erb'.
#
# [*timeout*]
# Execution timeout in seconds for the unzip command; 0 disables timeout,
# defaults to 300 seconds (5 minutes).
#
define php::unzip(
  $destination,
  $creates          = undef,
  $refreshonly      = false,
  $unless           = undef,
  $zipfile          = $name,
  $provider         = 'powershell',
  $options          = '20',
  $command_template = 'php/unzip.ps1.erb',
  $timeout          = 300,
) {
  validate_absolute_path($destination)

  if (! $creates and ! $refreshonly and ! $unless){
    fail("Must set one of creates, refreshonly, or unless parameters.\n")
  }

  exec { "unzip-${name}":
    command     => template($command_template),
    creates     => $creates,
    refreshonly => $refreshonly,
    unless      => $unless,
    provider    => $provider,
    timeout     => $timeout,
  }
}

# == Define: php::path
#
# Ensures the given directory (specified by the resource name or `path` parameter)
# is a part of the Windows System %PATH%.
#
# == Parameters
#
# [*directory*]
#  The directory to add the Windows PATH, defaults to the name of the resource.
#
# [*target*]
#  The location where the PATH variable is stored, must be either 'Machine'
#  (the default) or 'User'.
#
define php::path(
  $ensure    = 'present',
  $directory = $name,
  $target    = 'Machine',
) {
  # Ensure only valid parameters.
  validate_absolute_path($directory)
  validate_re($ensure, '^(present|absent)$', 'Invalid ensure parameter')
  validate_re($target, '^(Machine|User)$', 'Invalid target parameter')

  # Set the PATH environment variable, and refresh the environment.
  include php::refresh_environment
  exec { "windows-path-${name}":
    command  => template('php/path_set.ps1.erb'),
    unless   => template('php/path_check.ps1.erb'),
    provider => 'powershell',
    notify   => Class['php::refresh_environment'],
  }
}

# == Class: php
#
# Installs PHP
#
# === Parameters
#
# [ensure]
#   installed. No other values are currently supported.
#
# === Examples
#
#  class {'php':
#   ensure => installed,
#  }
#
# === Authors
#
# Pierrick Lozach <pierrick.lozach@inin.com>
#
# === Copyright
#
# Copyright 2015, Interactive Intelligence Inc.
#
class php::install (
  $ensure  = installed,
)
{

  # Define cache_dir
  $cache_dir = hiera('core::cache_dir', 'c:/users/vagrant/appdata/local/temp') # If I use c:/windows/temp then a circular dependency occurs when used with SQL
  if (!defined(File[$cache_dir]))
  {
    file {$cache_dir:
      ensure   => directory,
      provider => windows,
    }
  }

  case $ensure
  {
    installed:
    {
      # Check if php is installed? Which version?

      # Check if Microsoft C++ runtime is installed. If not, download and install it (http://download.microsoft.com/download/1/6/B/16B06F60-3B20-4FF2-B699-5E9B7962F9AE/VSU_4/vcredist_x64.exe)
      debug('Download Microsoft C++ runtime')
      download_file('vcredist_x64.exe', 'http://download.microsoft.com/download/1/6/B/16B06F60-3B20-4FF2-B699-5E9B7962F9AE/VSU_4/', $cache_dir, '', '')

      debug('Install Microsoft C++ Runtime')
      exec {'microsoft-c-runtime-install':
        command => "cmd.exe /c \"${cache_dir}\\vcredist_x64.exe /q /norestart",
        path    => $::path,
        cwd     => $::system32,
        unless  => 'reg query HKLM\SOFTWARE\Wow6432Node\Microsoft\VisualStudio\10.0\VC\VCRedist\x64 /f 1', # don't install it if it's already there
      }

      # Download PHP (http://windows.php.net/downloads/releases/php-5.6.12-nts-Win32-VC11-x64.zip)
      debug('Download PHP')
      download_file('php-5.6.12-nts-Win32-VC11-x64.zip', 'http://windows.php.net/downloads/releases/', $cache_dir, '', '')

      # Unzip to C:\PHP
      php::unzip { "${cache_dir}/php-5.6.12-nts-Win32-VC11-x64.zip":
        destination => 'C:/PHP',
        creates     => 'C:/PHP/php.ini-production',
      }

      # Add C:\PHP to PATH
      php::path { 'C:\\PHP':
        require => Unzip["${cache_dir}/php-5.6.12-nts-Win32-VC11-x64.zip"],
      }
      
      # Copy php.ini template
      file { 'C:\\PHP\\php.ini':
        ensure  => file,
        content => template('php/php.ini.erb'),
        require => Unzip["${cache_dir}/php-5.6.12-nts-Win32-VC11-x64.zip"],
      }


      # Create IIS FactCGI process pool: %windir%\system32\inetsrv\appcmd set config /section:system.webServer/fastCGI ^/+[fullPath='c:\PHP\php-cgi.exe']
      # Create handle mapping for PHP requests: %windir%\system32\inetsrv\appcmd set config /section:system.webServer/handlers ^/+[name='PHP_via_FastCGI', path='*.php',verb='*',modules='FastCgiModule',^scriptProcessor='c:\PHP\php-cgi.exe',resourceType='Either']
      # (optional) Grant write permissions to a folder: icacls <folder> /grant IUSR:(OI)(CI)(M)
      # (optional) Set index.php as the default document: %windir%\system32\inetsrv\appcmd.exe set config ^-section:system.webServer/defaultDocument /+"files.[value='index.php']" ^/commit:apphost
      # (optional) Configure FastCGI and PHP recycling: 
      #   %windir%\system32\inetsrv\appcmd.exe set config -section:system.webServer/fastCgi ^/[fullPath='c:\php\php-cgi.exe'].instanceMaxRequests:10000
      #   %windir%\system32\inetsrv\appcmd.exe set config -section:system.webServer/fastCgi ^/+"[fullPath='C:\php\php-cgi.exe'].environmentVariables.^[name='PHP_FCGI_MAX_REQUESTS',value='10000']"
      # (optional) Configure FastCGI timeout:
      #   %windir%\system32\inetsrv\appcmd.exe set config -section:system.webServer/fastCgi ^/[fullPath='C:\php\php-cgi.exe',arguments=''].activityTimeout:"90"  /commit:apphost
      #   %windir%\system32\inetsrv\appcmd.exe set config -section:system.webServer/fastCgi ^/[fullPath='C:\php\php-cgi.exe',arguments=''].requestTimeout:"90"  /commit:apphost
      # Run iisreset
    }
    default:
    {
      fail("Unsupported ensure \"${ensure}\"")
    }
  }
}