# == Class: php::refresh_environment
#
# Refresh the Windows Environment.  Makes it possible to have updated Windows
# environment variables (e.g., the %Path%) without logging off or restarting.
#
class php::refresh_environment(
  $command_template = 'php/refresh_environment.ps1.erb',
  $refreshonly      = true,
  $unless           = undef,
  $onlyif           = undef,
  $provider         = 'powershell',
){
  exec { 'windows-refresh-environemnt':
    command     => template($command_template),
    refreshonly => $refreshonly,
    unless      => $unless,
    onlyif      => $onlyif,
    provider    => $provider,
  }
}