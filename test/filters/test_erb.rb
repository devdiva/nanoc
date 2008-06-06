require 'helper'

class Nanoc::Filters::ERBTest < Test::Unit::TestCase

  def setup    ; global_setup    ; end
  def teardown ; global_teardown ; end

  def test_filter
    assert_nothing_raised do
      with_temp_site do |site|
        # Get filter
        filter = ::Nanoc::Filters::ERB.new(site.pages.first.to_proxy, site)

        # Run filter
        result = filter.run('<%= "Hello." %>')
        assert_equal('Hello.', result)
      end
    end
  end

end