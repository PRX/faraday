require File.expand_path(File.join(File.dirname(__FILE__), 'helper'))
require 'rack/utils'

Faraday::CompositeReadIO.send :attr_reader, :ios

class RequestMiddlewareTest < Faraday::TestCase
  def setup
    @conn = Faraday.new do |b|
      b.request :multipart
      b.request :url_encoded
      b.request :json
      b.adapter :test do |stub|
        stub.post('/echo') do |env|
          posted_as = env[:request_headers]['Content-Type']
          [200, {'Content-Type' => posted_as}, env[:body]]
        end
      end
    end
  end

  def test_does_nothing_without_payload
    response = @conn.post('/echo')
    assert_nil response.headers['Content-Type']
    assert response.body.empty?
  end

  def test_ignores_custom_content_type
    response = @conn.post('/echo', { :some => 'data' }, 'content-type' => 'application/x-foo')
    assert_equal 'application/x-foo', response.headers['Content-Type']
    assert_equal({ :some => 'data' }, response.body)
  end

  def test_json_encodes_hash
    response = @conn.post('/echo', { :fruit => %w[apples oranges] }, 'content-type' => 'application/json')
    assert_equal 'application/json', response.headers['Content-Type']
    assert_equal '{"fruit":["apples","oranges"]}', response.body
  end

  def test_json_skips_encoding_for_strings
    response = @conn.post('/echo', '{"a":"b"}', 'content-type' => 'application/json')
    assert_equal 'application/json', response.headers['Content-Type']
    assert_equal '{"a":"b"}', response.body
  end

  def test_json_fails_with_useful_message_when_no_json_adapter_available
    without_json_adapter do
      expected_msg = "No JSON adapter available. Install either activesupport or yajl-ruby."
      # assert_raise doesn't work to check the message (at least on 1.8.7)
      begin
        @conn.post('/echo', { :fruit => %w[apples oranges] }, 'content-type' => 'application/json')
        fail "Exception not raised"
      rescue Faraday::Error::MissingDependency => e
        assert_equal expected_msg, e.message
      end
    end
  end

  def test_url_encoded_does_not_fail_when_no_json_adapter_available
    without_json_adapter do
      assert_nothing_raised {
        @conn.post('/echo', { :fruit => %w[apples oranges] })
      }
    end
  end

  def without_json_adapter
    original_adapter = Faraday::Request::JSON.adapter
    Faraday::Request::JSON.adapter = nil
    begin
      yield
    ensure
      Faraday::Request::JSON.adapter = original_adapter
    end
  end

  def test_url_encoded_no_header
    response = @conn.post('/echo', { :fruit => %w[apples oranges] })
    assert_equal 'application/x-www-form-urlencoded', response.headers['Content-Type']
    assert_equal 'fruit[]=apples&fruit[]=oranges', response.body
  end

  def test_url_encoded_with_header
    response = @conn.post('/echo', {'a'=>123}, 'content-type' => 'application/x-www-form-urlencoded')
    assert_equal 'application/x-www-form-urlencoded', response.headers['Content-Type']
    assert_equal 'a=123', response.body
  end

  def test_url_encoded_nested
    response = @conn.post('/echo', { :user => {:name => 'Mislav', :web => 'mislav.net'} })
    assert_equal 'application/x-www-form-urlencoded', response.headers['Content-Type']
    expected = { 'user' => {'name' => 'Mislav', 'web' => 'mislav.net'} }
    assert_equal expected, Rack::Utils.parse_nested_query(response.body)
  end

  def test_multipart
    # assume params are out of order
    regexes = [
      /name\=\"a\"/,
      /name=\"b\[c\]\"\; filename\=\"request_middleware_test\.rb\"/,
      /name=\"b\[d\]\"/]

    payload = {:a => 1, :b => {:c => Faraday::UploadIO.new(__FILE__, 'text/x-ruby'), :d => 2}}
    response = @conn.post('/echo', payload)

    assert_kind_of Faraday::CompositeReadIO, response.body
    assert_equal "multipart/form-data;boundary=%s" % Faraday::Request::Multipart::DEFAULT_BOUNDARY,
      response.headers['Content-Type']

    response.body.send(:ios).map{|io| io.read}.each do |io|
      if re = regexes.detect { |r| io =~ r }
        regexes.delete re
      end
    end
    assert_equal [], regexes
  end
  
  def test_multipart_with_arrays
    # assume params are out of order
    regexes = [
      /name\=\"a\"/,
      /name=\"b\[\]\[c\]\"\; filename\=\"request_middleware_test\.rb\"/,
      /name=\"b\[\]\[d\]\"/]

    payload = {:a => 1, :b =>[{:c => Faraday::UploadIO.new(__FILE__, 'text/x-ruby'), :d => 2}]}
    response = @conn.post('/echo', payload)

    assert_kind_of Faraday::CompositeReadIO, response.body
    assert_equal "multipart/form-data;boundary=%s" % Faraday::Request::Multipart::DEFAULT_BOUNDARY,
      response.headers['Content-Type']

    response.body.send(:ios).map{|io| io.read}.each do |io|
      if re = regexes.detect { |r| io =~ r }
        regexes.delete re
      end
    end
    assert_equal [], regexes
  end
  
end
