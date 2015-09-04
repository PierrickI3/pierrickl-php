require 'puppetlabs_spec_helper/module_spec_helper'
require 'spec_helper'

describe 'php::install' do

  context 'with defaults for all parameters' do
    it { should contain_class('php::install') }
  end

end