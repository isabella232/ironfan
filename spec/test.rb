require 'simplecov'
require 'simplecov-rcov'

SimpleCov.formatter = SimpleCov::Formatter::RcovFormatter
SimpleCov.start

describe "ironfan" do
  describe 'successfuly runs example' do
    it "should return true" do
      puts "this is a test"
    end
  end
end