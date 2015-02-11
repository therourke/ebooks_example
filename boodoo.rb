require 'twitter_ebooks'
require 'cloudinary'

include Ebooks

## Retweet check based on Really-Existing-RT practices
class Ebooks::TweetMeta
  def is_retweet?
    tweet.retweeted_status? || !!tweet.text[/[RM]T ?[@:]/i]
  end
end

module Ebooks::Boodoo
  # check if we're configured to use Cloudinary for cloud storage
  def has_cloud?
    (ENV['CLOUDINARY_URL'].nil? || ENV['CLOUDINARY_URL'].empty?) ? false : true
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

  def make_client
    Twitter::REST::Client.new do |config|
      config.consumer_key = @consumer_key
      config.consumer_secret = @consumer_secret
      config.access_token = @access_token
      config.access_token_secret = @access_token_secret
    end
  end

  def jsonify(paths)
    paths.each do |path|
      name = File.basename(path).split('.')[0]
      ext = path.split('.')[-1]
      new_path = name + ".json"
      lines = []
      id = nil

      if ext.downcase == "json"
        log "Taking no action on JSON corpus at #{path}"
        return
      end

      content = File.read(path, :encoding => 'utf-8')

      if ext.downcase == "csv" #from twitter archive
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

      # BELOW IS FOR FILE-SYSTEM; NEED TO ALTER FOR CLOUDINARY/REQUEST?
      File.open(new_path, 'w') do |f|
        log "Writing #{lines.length} lines to #{new_path}"
        f.write(JSON.pretty_generate(lines))
      end
    end
  end
end

class Ebooks::Boodoo::CloudArchive < Ebooks::Archive
  def initialize(username, path=nil, client=nil)
    # Just bail on everything if we aren't using Cloudinary
    return super unless has_cloud?
    # Otherwise duplicate a lot of super(), but also use ~~THE CLOUD~~
    @username = username
    @path = path || "corpus/#{username}.json"
    if File.directory?(@path)
      @path = File.join(@path, "#{username}.json")
    end
    @basename = File.basename(@path)
    @client = client || Boodoo.make_client
    @url = Cloudinary::Utils.cloudinary_url(@basename, :resource_type=>:raw)
    fetch!
    parse!
    sync
    # save! # #sync automatically saves
    persist

    if @tweets.empty?
      log "New archive for @#{@username} at #{@url}"
    else
      log "Currently #{@tweets.length} tweets for #{@username}"
    end
  end

  def persist(public_id=nil)
    public_id ||= @basename
    log "Deleting out-dated archive ~~~FROM THE CLOUD~~~"
    Cloudinary::Api.delete_resources(public_id, :resource_type=>:raw)
    log "Uploading JSON archive ~~TO THE CLOUD~~"
    res = Cloudinary::Uploader.upload(@path, :resource_type=>:raw, :public_id=>public_id, :invalidate=>true)
    log "Upload complete!"
    res
  end

  def persist!
    persist(@basename)
  end

  def parse(content=nil)
    content = content || @content || '[]'
    JSON.parse(content, symbolize_names: true)
  end

  def parse!(content=nil)
    @tweets = parse(content)
  end

  def save(path=nil)
    path ||= @path
    File.open(path, 'w') do |f|
      f.write(JSON.pretty_generate(@tweets))
    end
  end

  def save!
    save(@path)
  end

  def fetch(url=nil)
    url ||= @url
    log "Fetching JSON archive ~~~FROM THE CLOUD~~~"
    content = Cloudinary::Downloader.download(url)
    if content.empty?
      log "WARNING: JSON archive not found ~~~IN THE CLOUD~~~"
      nil
    else
      log "Download complete!"
      content
    end
  end

  def fetch!
    @content = fetch
  end
end

class Ebooks::Boodoo::CloudModel < Ebooks::Model
  # Read a saved model from marshaled content instead of file
  # @param content [String]
  # @return [Ebooks::Boodoo::CloudModel]
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

  def initialize(username, path=nil)
    return Ebooks::Model.new unless has_cloud?
    @path = path || "corpus/#{username}.model"
    if File.directory?(@path)
      @path = File.join(@path, "#{username}.model")
    end
    super()
    @basename = File.basename(@path)
  end

  # Create a model from JSON string
  # @content [String] Ebooks-style JSON twitter archive
  # @return [Ebooks::Boodoo::CloudModel]
  def from_json(content)
    log "Reading json corpus with length #{content.size}"
    lines = JSON.parse(content).map do |tweet|
      tweet['text']
    end
    consume_lines(lines)
  end

  def persist(public_id=nil)
    public_id ||= @basename
    log "Deleting old model ~~~FROM THE CLOUD~~~"
    Cloudinary::Api.delete_resources(@basename, :resource_type=>:raw)
    log "Uploading bot model ~~TO THE CLOUD~~"
    res = Cloudinary::Uploader.upload(@path, :resource_type=>:raw, :public_id=>public_id, :invalidate=>true)
    log "Upload complete!"
    res
  end

  def persist!
    persist(@basename)
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

  def fetch!
    @content = fetch
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
    if @blacklist.map(&:downcase).include?(username.downcase)
      true
    else
      false
    end
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
