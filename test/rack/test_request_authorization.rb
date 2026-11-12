require "minitest/autorun"
require "rack/test"
require "json"
require "logger"
require_relative "../../lib/ontologies_linked_data"
require_relative "../../config/config.rb"

LOGGER = Logger.new($stdout)
ENV["rack.test"] = "true"


class TestRackAuthorization < Minitest::Test
  include Rack::Test::Methods

  def app
    eval "Rack::Builder.new {( " + File.read(File.dirname(__FILE__) + '/authorization.ru') + "\n )}"
  end

  def setup
    _variables
    _delete_user
    users = _create_user
    user = users.shift
    user1 = users.shift
    @apikey = user.apikey
    @admin = _create_admin
    @userapikey = user1.apikey
    @security = LinkedData.settings.enable_security
    LinkedData.settings.enable_security = true
  end

  def teardown
    Thread.current[:remote_user] = nil
    LinkedData.settings.enable_security = @security
    _delete_user
  end

  def _variables
    @usernames = ["test_username", "user2", "test_admin"]
  end

  def _create_user
    users = []
    (@usernames - ["test_admin"]).each do |username|
      user = LinkedData::Models::User.new({
        username: username,
        password: "test_password",
        email: "test_email#{rand}@example.org"
      })
      user.save unless user.exist?
      users << user
    end
    users
  end

  def _create_admin
    admin = LinkedData::Models::User.new({
      username: "test_admin",
      password: "test_password",
      email: "test_admin#{rand}@example.org",
      role: [LinkedData::Models::Users::Role.find(LinkedData::Models::Users::Role::ADMIN).include(:role).first]
    })
    admin.save
    admin
  end

  def _delete_user
    @usernames.each do |username|
      user = LinkedData::Models::User.find(username).first
      user.delete unless user.nil?
    end
  end

  def test_authorize
    get "/ontologies"
    assert last_response.status == 401
    get "/ontologies", {}, {"Authorization" => 'apikey token="'+@apikey+''+'"'}
    assert last_response.status == 200
    apikey = MultiJson.load(last_response.body)
    assert @apikey.eql?(apikey)
    get "/ontologies", {}, {"Authorization" => "apikey token=#{@apikey}"}
    assert last_response.status == 200
    apikey = MultiJson.load(last_response.body)
    assert @apikey.eql?(apikey)
    get "/ontologies?apikey=#{@apikey}"
    assert last_response.status == 200
    apikey = MultiJson.load(last_response.body)
    assert @apikey.eql?(apikey)
    get "/ontologies", {}, {"Authorization" => 'apikey token="'+@apikey+'&userapikey='+@userapikey+'"'}
    assert last_response.status == 200
    apikey = MultiJson.load(last_response.body)
    assert @userapikey.eql?(apikey)
    get "/ontologies", {}, {"Authorization" => "apikey token=#{@apikey}&userapikey=#{@userapikey}"}
    assert last_response.status == 200
    apikey = MultiJson.load(last_response.body)
    assert @userapikey.eql?(apikey)
    get "/ontologies?apikey=#{@apikey}&userapikey=#{@userapikey}"
    assert last_response.status == 200
    apikey = MultiJson.load(last_response.body)
    assert @userapikey.eql?(apikey)
  end

  def test_remote_user_set_only_during_request
    get "/current_user?apikey=#{@apikey}"
    assert_equal 200, last_response.status
    body = MultiJson.load(last_response.body)
    assert_equal "test_username", body["env"]
    assert_equal "test_username", body["thread"]
    assert_nil Thread.current[:remote_user]
  end

  def test_remote_user_cleared_when_apikey_is_missing_or_rejected
    get "/current_user?apikey=#{@admin.apikey}"
    assert_equal 200, last_response.status

    get "/current_user"
    assert_equal 401, last_response.status
    assert_nil Thread.current[:remote_user]

    Thread.current[:remote_user] = @admin
    get "/current_user?apikey=not-a-real-apikey"
    assert_equal 401, last_response.status
    assert_nil Thread.current[:remote_user]
  end

  def test_bypassed_request_runs_without_a_user
    referer = { "HTTP_REFERER" => LinkedData.settings.rest_url_prefix }

    get "/current_user?apikey=#{@admin.apikey}"
    assert_equal "test_admin", MultiJson.load(last_response.body)["thread"]

    get "/current_user", {}, referer
    assert_equal 200, last_response.status
    body = MultiJson.load(last_response.body)
    assert_nil body["env"]
    assert_nil body["thread"]

    Thread.current[:remote_user] = @admin
    get "/current_user", {}, referer
    assert_nil MultiJson.load(last_response.body)["thread"]
  end

  def test_bypassed_request_cannot_write_as_an_earlier_user
    referer = { "HTTP_REFERER" => LinkedData.settings.rest_url_prefix }
    original_apikey = LinkedData::Models::User.find("user2").include(:apikey).first.apikey

    get "/change_apikey?apikey=#{@admin.apikey}&username=user2"
    assert_equal 200, last_response.status
    changed_apikey = LinkedData::Models::User.find("user2").include(:apikey).first.apikey
    refute_equal original_apikey, changed_apikey

    get "/change_apikey", { "username" => "user2" }, referer
    assert_equal 403, last_response.status

    Thread.current[:remote_user] = @admin
    get "/change_apikey", { "username" => "user2" }, referer
    assert_equal 403, last_response.status

    assert_equal changed_apikey, LinkedData::Models::User.find("user2").include(:apikey).first.apikey
  end

end
