require 'twitter_ebooks'
require 'cloudinary'
require 'time_difference'

include Ebooks

## Retweet check based on Really-Existing-RT practices
class Ebooks::TweetMeta
  def is_retweet?
    tweet.retweeted_status? || !!tweet.text[/[RM]T ?[@:]/i]
  end
end

module Ebooks::Boodoo

  def self.make_Model(username: nil, path: nil, ignore_cloud: false)
    # return CloudModel unless Cloudinary is missing or instructed not to.
    if !ignore_cloud && has_cloud?
      CloudModel.new(username, path: path)
    else
      Model.new
    end
  end

  def self.make_Archive(username, path: nil, client: nil, content: nil, local: false, ignore_cloud: false)
    # return CloudArchive unless Cloudinary is missing or instructed not to.
    if !ignore_cloud && has_cloud?
      CloudArchive.new(username, path: path, client: client, content: content, local: local)
    else
      Archive.new(username, path, client)
    end
  end

  def age(since, now: Time.now, unit: :in_hours)
    since ||= Time.new(1986, 2, 8)
    unit = unit.to_sym
    TimeDifference.between(since, now).method(unit).call
  end

  def self.age(since, now: Time.now, unit: :in_hours)
    age(since, now, unit)
  end

  # check if we're configured to use Cloudinary for cloud storage
  def has_cloud?
    (ENV['CLOUDINARY_URL'].nil? || ENV['CLOUDINARY_URL'].empty?) ? false : true
  end

  # def self.has_cloud?
  #   has_cloud?
  # end

  def in_cloud?(public_id, resource_type=:raw)
    return false if !has_cloud?
    begin
      Cloudinary::Api.resource(public_id, :resource_type=>resource_type)
      true
    rescue Cloudinary::Api::NotFound
      false
    end
  end

  # supports Ruby Range literal, Fixnum, or Float as string
  def parse_num(value)
    eval(value.to_s[/^\d+(?:\.{1,3})?\d*$/].to_s)
  end

  # Make expected/possible Range
  def parse_range(value)
    value = parse_num(value)
    if value.nil?
      value = nil
    elsif !value.respond_to?(:to_a)
      value = Range.new(value, value)
    end
    value
  end

  def obscure_curse(len)
    s = []
    c = ['!', '@', '$', '%', '^', '&', '*']
    len.times do
      s << c.sample
    end
    s.join('')
  end

  def obscure_curses(tweet)
    # TODO: Ignore banned terms that are part of @-mentions
    $banned_terms.each do |term|
      re = Regexp.new("\\b#{term}\\b", "i")
      tweet.gsub!(re, Ebooks::Boodoo.obscure_curse(term.size))
    end
    tweet
  end

  def parse_array(value, array_splitter=nil)
    array_splitter ||= / *[,;]+ */
    value.split(array_splitter).map(&:strip)
  end

  def new_client
    Twitter::REST::Client.new do |config|
      config.consumer_key = ENV['CONSUMER_KEY']
      config.consumer_secret = ENV['CONSUMER_SECRET']
      config.access_token = ENV['ACCESS_TOKEN']
      config.access_token_secret = ENV['ACCESS_TOKEN_SECRET']
    end
  end

  def minify_tweets(tweets)
    log "Minifying tweets..."
    tweets.map do |tweet|
      {id: tweet[:id], text: tweet[:text]}
    end
  end

  def jsonify(path, write_file: true, from_cloud: false, to_cloud: true, new_name: nil)
    basename = File.basename(path)
    name = basename.split('.')[0]
    ext = path.split('.')[-1]
    new_name ||= name

    new_path = "corpus/#{new_name}.json"
    lines = []
    id = nil

    #TODO: Move this to its own method: find_corpus(basename)
    if from_cloud && in_cloud?(basename)
      log "Reading initial corpus file ~~~FROM CLOUD~~~"
      content = Cloudinary::Downloader.download(path, :resource_type=>:raw)
    else
      log "Reading local initial corpus file"
      content = File.read(path, :encoding => 'utf-8')
    end

    if ext.downcase == "json"
      log "Minifying JSON corpus at #{path}"
      lines = minify_tweets(JSON.parse(content, :symbolize_names=>true))
    elsif ext.downcase == "csv" #from twitter archive
      log "Reading CSV corpus from #{path}"
      content = CSV.parse(content)
      header = content.shift
      text_col = header.index('text')
      id_col = header.index('tweet_id')
      lines = content.map do |tweet|
        id = tweet[id_col].empty? ? 0 : tweet[id_col]
        {id: id, text: tweet[text_col]}
      end
    else
      log "Reading plaintext corpus from #{path}"
      lines = content.split("\n").map do |line|
        {id: 0, text: line}
      end
    end

    File.open(new_path, 'w') do |f|
      log "Writing #{lines.length} lines to #{new_path}"
      f.write(JSON.generate(lines))
    end if write_file

    #TODO: Save res["url"] to CloudArchive somehow?
    if to_cloud && has_cloud?
      public_id = new_path
      # log "Deleting JSON archive ~~~FROM THE CLOUD~~~"
      # Cloudinary::Api.delete_resources(public_id, :resource_type=>:raw)
      log "Uploading JSON archive ~~TO THE CLOUD~~"
      res = Cloudinary::Uploader.upload(new_path, :resource_type=>:raw, :public_id=>public_id, :invalidate=>true)
      log "Upload complete"
      {url: res["url"], lines: JSON.generate(lines)}
    else
      {url: nil, lines: JSON.generate(lines)}
    end
  end
end

class Ebooks::Archive
  def self.exist?(basename)
    File.exist?("corpus/#{basename}")
  end

  def parse(content=nil)
    content = content || @content || '[]'
    JSON.parse(content, symbolize_names: true)
  end

  def parse!(content=nil)
    @tweets = parse(content)
  end

 def minify
    minify_tweets(@tweets)
  end

  def minify!
    @tweets = minify_tweets(@tweets)
  end

 def persist(path=nil)
    path ||= @path
    log "Saving JSON archive locally..."
    File.open(path, 'w') do |f|
      f.write(JSON.pretty_generate(@tweets))
    end
    log "Save complete!"
    @path
  end

  def persist!
    persist(@path)
  end

  def save(path=nil)
    persist(path)
  end

  def save!
    save(@path)
  end
end

class Ebooks::Boodoo::CloudArchive < Ebooks::Archive
  include Ebooks::Boodoo

  def self.exist?(username)
    begin
      Cloudinary::Api.resource("#{username}.json", :resource_type=>:raw)
      true
    rescue Cloudinary::Api::NotFound
      false
    end
  end

  def initialize(username, path: nil, client: nil, content: nil, local: false)
    # Otherwise duplicate a lot of super(), but also use ~~THE CLOUD~~
    @username = username
    @path = path || "corpus/#{username}.json"
    if File.directory?(@path)
      @path = File.join(@path, "#{username}.json")
    end
    @basename = File.basename(@path)
    @client = client || new_client
    @url = Cloudinary::Utils.cloudinary_url(@basename, :resource_type=>:raw)
    @public_id = @basename
    if local || content
      @content = content || File.read(@path)
    else
      fetch!
    end
    parse!
    new_tweets = sync.class != IO
    persist if new_tweets

    if @tweets.empty?
      log "New archive for @#{@username} at #{@url}"
    else
      log "Currently #{@tweets.length} tweets for #{@username}"
    end
  end

  def persist(public_id=nil)
    public_id ||= @basename
    # log "Deleting out-dated archive ~~~FROM THE CLOUD~~~"
    # Cloudinary::Api.delete_resources(public_id, :resource_type=>:raw)
    log "Uploading JSON archive ~~TO THE CLOUD~~"
    res = Cloudinary::Uploader.upload(@path, :resource_type=>:raw, :public_id=>public_id, :invalidate=>true)
    @url = res["url"]
    @persisted = Time.now
    log "Upload complete!"
    res
  end

  def since_persisted
    Boodoo.age(@persisted, Time.now)
  end

  # Unused method?
  def save(path=nil, minify=true)
    path ||= @path
    output = minify ? JSON.generate(minify) : JSON.pretty_generate(@tweets)
    File.open(path, 'w') do |f|
      f.write(output)
    end
  end

  def fetch(url=nil)
    url ||= @url
    log "Fetching JSON archive ~~~FROM THE CLOUD~~~"
    content = Cloudinary::Downloader.download(url, :resource_type=>:raw)
    if content.empty?
      log "WARNING: JSON archive not found ~~~IN THE CLOUD~~~"
      @fetched = nil
      nil
    else
      log "Download complete!"
      @fetched = Time.now
      content
    end
  end

  def fetch!
    @content = fetch
  end

  def since_fetched
    Boodoo.age(@fetched, Time.now)
  end
end

class Ebooks::Model
  # add methods here to match Boodoo::CloudModel
  def self.parse(content)
    model = Model.new
    model.instance_eval do
      props = Marshal.load(content)
      @tokens = props[:tokens]
      @sentences = props[:sentences]
      @mentions = props[:mentions]
      @keywords = props[:keywords]
    end
    model
  end

  def self.from_json(content, is_path: nil)
    model = Model.new
    model.from_json(content, is_file)
    model
  end

  # Create a model from JSON string
  # @content [String/Array] Ebooks-style JSON twitter archive
  # @return [Ebooks::Model]
  def from_json(content, is_path: false)
    content = File.read(content, :encoding => 'utf-8') if is_path
    if content.respond_to?(:upcase)
      lines = JSON.parse(content).map do |tweet|
        tweet['text']
      end
    else
      lines = content
    end
    log "Reading json corpus with #{lines.size} lines"
    consume_lines(lines)
  end

  def fetch(path=nil)
    path ||= @path
    if File.exist?(path)
      log "Fetching local bot model"
      content = File.read(@path, :encoding => 'utf-8')
      if !content.empty?
        log "local model fetched"
        return content
      end
    end
    log "WARNING: local bot model not found"
    return nil
  end

  def fetch!
    @content = fetch
  end

  def parse(content=nil)
    props = Marshal.load(content)
  end

  def parse!(content=nil)
    props = parse(content)
    @tokens = props[:tokens]
    @sentences = props[:sentences]
    @mentions = props[:mentions]
    @keywords = props[:keywords]
  end

  def save!
    save(@path)
  end

  def persist(path=nil)
    path ||= @path
    save(path)
  end

  def persist!
    persist
  end
end

class Ebooks::Boodoo::CloudModel < Ebooks::Model
  # Read a saved model from marshaled content instead of file
  # @param content [String]
  # @return [Ebooks::Boodoo::CloudModel]
  def self.parse(content)
    model = CloudModel.new
    model.instance_eval do
      props = Marshal.load(content)
      @tokens = props[:tokens]
      @sentences = props[:sentences]
      @mentions = props[:mentions]
      @keywords = props[:keywords]
    end
    model
  end

  def self.from_json(content, is_file)
    model = CloudModel.new
    model.from_json(content, is_file)
    model
  end

  def initialize(username, path: nil)
    @path = path || "corpus/#{username}.model"
    if File.directory?(@path)
      @path = File.join(@path, "#{username}.model")
    end
    super()
    @basename = File.basename(@path)
    @url = Cloudinary::Utils.cloudinary_url(@basename, :resource_type=>:raw)
  end

  def persist(public_id=nil)
    public_id ||= @basename
    log "Uploading bot model ~~TO THE CLOUD~~"
    res = Cloudinary::Uploader.upload(@path, :resource_type=>:raw, :public_id=>public_id, :invalidate=>true)
    @url = res["url"]
    log "Upload complete!"
    res
  end

  def persist!
    persist(@basename)
  end

  def fetch(url=nil)
    url ||= @url
    log "Fetching bot model ~~~FROM THE CLOUD~~~"
    content = Cloudinary::Downloader.download(url)
    if content.empty?
      log "WARNING: bot model not found ~~~IN THE CLOUD~~~"
      nil
    else
      log "Download complete!"
      content
    end
  end
end

class Ebooks::Boodoo::BoodooBot < Ebooks::Bot
  $required_fields = ['consumer_key', 'consumer_secret',
                      'access_token', 'access_token_secret',
                      'bot_name', 'original']

  # Unfollow a user -- OVERRIDE TO FIX TYPO
  # @param user [String] username or user id
  def unfollow(user, *args)
    log "Unfollowing #{user}"
    twitter.unfollow(user, *args)
  end

  # A rough error-catch/retry for rate limit, dupe fave, server timeouts
  def catch_twitter
    begin
      yield
    rescue Twitter::Error => error
      @retries += 1
      raise if @retries > @max_error_retries
      if error.class == Twitter::Error::TooManyRequests
        reset_in = error.rate_limit.reset_in
        log "RATE: Going to sleep for ~#{reset_in / 60} minutes..."
        sleep reset_in
        retry
      elsif error.class == Twitter::Error::Forbidden
        # don't count "Already faved/followed" message against attempts
        @retries -= 1 if error.to_s.include?("already")
        log "WARN: #{error.to_s}"
        return true
      elsif ["execution", "capacity"].any?(&error.to_s.method(:include?))
        log "ERR: Timeout?\n\t#{error}\nSleeping for #{@timeout_sleep} seconds..."
        sleep @timeout_sleep
        retry
      else
        log "Unhandled exception from Twitter: #{error.to_s}"
        raise
      end
    end
  end

  # Override Ebooks::Bot#blacklisted? to ensure lower<=>lower check
  def blacklisted?(username)
    @blacklist.map(&:downcase).include?(username.downcase)
  end

  # Follow new followers, unfollow lost followers
  def follow_parity
    followers = catch_twitter { twitter.followers(:count=>200).map(&:screen_name) }
    following = catch_twitter { twitter.following(:count=>200).map(&:screen_name) }
    to_follow = followers - following
    to_unfollow = following - followers
    twitter.follow(to_follow) unless to_follow.empty?
    twitter.unfollow(to_unfollow) unless to_unfollow.empty?
    @followers = followers
    @following = following - to_unfollow
    if !(to_follow.empty? || to_unfollow.empty?)
      log "Followed #{to_follow.size}; unfollowed #{to_unfollow.size}."
    end
  end

  def make_model!
    log "Updating model: #{@model_path}"
    Ebooks::Model.consume(@archive_path).save(@model_path)
    log "Loading model..."
    @model = Ebooks::Model.load(@model_path)
  end

  def can_run?
    missing_fields.empty?
  end

  def missing_fields
    $required_fields.select { |field|
      # log "#{field} = #{send(field)}"
      send(field).nil? || send(field).empty?
    }
  end
end
