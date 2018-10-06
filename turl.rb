#!/usr/bin/env ruby
# frozen_string_literal: true

require 'rubygems'
require 'sequel'
require 'ramaze'
require 'base62'

DB = Sequel.sqlite('turl.db')
BASE_URL = 'http://localhost:7000/'.freeze

Sequel::Model.plugin(:schema)
Sequel::Model.plugin(:hook_class_methods)
Sequel::Model.plugin(:validation_class_methods)

#
#  Model
#
class TinyURL < Sequel::Model(:turl)
  set_schema do
    primary_key :id
    varchar     :url
    integer     :hits
    timestamp   :created
    index [:url], unique: true
    index [:created]
    index [:hits]
  end

  validates do
    presence_of :url
  end

  validates_each :url do |object, attribute, value|
    u = URI.parse(value)
    object.errors[attribute] << 'Invalid URL' unless 
      u.absolute? && ['http', 'https'].member?(u.scheme)
    
  end

  after_create do
    update(created: Time.now, hits: 1)
  end

  def to_turl
    id.base62_encode
  end

  def self.add(uri)
    t = TinyURL.new(url: uri)
    return nil unless t && t.valid?

    t.save
    t.to_turl
  end

  def self.pack(uri, prefix = BASE_URL)
    exists = TinyURL[url: uri]
    turl = exists ? exists.to_turl : TinyURL.add(uri)
    return nil if turl.nil?

    # insert the link once more if the turl value equals a controller name.
    turl = TinyURL.add(uri) if ['index', 'login', 'logout'].member?(turl)
    "#{prefix}#{turl}"
  end

  def self.unpack(turl)
    return nil unless t = find_by_turl(turl)

    t.update(hits: t.hits.to_i + 1)
    t.url
  end

  def self.count(turl)
    return 0 unless t = find_by_turl(turl)

    t.hits
  end

  def self.find_by_turl(turl)
    return nil unless turl =~ /^([A-Za-z0-9])+$/

    TinyURL[id: turl.base62_decode]
  end
end

TinyURL.create_table unless TinyURL.table_exists?

#
# Controller and View
#

class MainController < Ramaze::Controller
  unless defined? AUTHS
    AUTHS = {
      'admin' => 'e5e9fa1ba31ecd1ae84f75caaa474f3a663f05f4' # Digest::SHA1.hexdigest('secret')
    }.freeze
  end

  helper :auth
  trait auth_table: AUTHS

  before(:_api) do
    response['WWW-Authenticate'] = %(Basic realm="Login Required")
    respond 'Unauthorized', 401 unless http_authenticated?
  end

  before(:_add) { login_required }
  before(:login){ redirect r('/') if logged_in? }

  layout :_page

  def index(turl = nil, *_params)
    if turl
      url = TinyURL.unpack(turl)
      redirect(url || rs)
    end
    ''
  end

  def _add
    redirect(rs) unless request.post?
    turl = TinyURL.pack(request[:url])
    return 'Invalid input!<br/><br/>' if turl.nil?

    "Tiny URL: <a href=\"#{turl}\">#{turl}</a><br/><br/>"
  end

  # _api?turl=http://... will return short url
  # _api?url=.. will restore the original url
  # _api?hits=.. will return the number of hits to given turl
  def _api
    res = TinyURL.pack(request[:turl]) if request[:turl]
    res = TinyURL.unpack(request[:url].split('/').last) if request[:url]
    res = TinyURL.count(request[:hits].split('/').last).to_s if request[:hits]
    res ||= ''
    respond res
  end

  def _page
    %{
<html>
  <head>
    <title>TinyURL Service</title>
  </head>
  <body>
    #{@content}
    <?r if logged_in? ?>
    <form id="tinyurl" method="post" action="#{r(:_add)}">
      <div>
        Enter long URL:
        <input id="url" name="url" type="text" />
        <input type="submit" value="Pack" />
      </div>
    </form>
    <p>#{a 'Logout', :logout}</p>
    <?r else ?>
    <p>#{a 'Login', :login}</p>
    <?r end ?>
  </body>
</html>
    }
  end

  private

  def http_authenticated?
    (auth = request.env['HTTP_AUTHORIZATION']) &&
    (u, p = auth.split.last.unpack1('m').split(':', 2)) &&
    (AUTHS[u] == Digest::SHA1.hexdigest(p))
  end
end

if $PROGRAM_NAME == __FILE__
  Ramaze::Log.loggers = [Logger.new('turl.log')]
  begin
    require 'mongrel'
    Ramaze.start adapter: :mongrel, port: 7000
  rescue LoadError
    Ramaze.start adapter: :webrick, port: 7000
  end
end
