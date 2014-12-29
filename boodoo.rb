require 'twitter_ebooks'
include Ebooks

module Ebooks::Boodoo
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
end

## Retweet check based on Really-Existing-RT practices
class Ebooks::TweetMeta
  def is_retweet?
    tweet.retweeted_status? || !!tweet.text[/[RM]T ?[@:]/i]
  end
end

class Ebooks::Boodoo::BoodooBot < Ebooks::Bot
  $required_fields = ['consumer_key', 'consumer_secret',
                      'access_token', 'access_token_secret',
                      'bot_name', 'original']

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

  def has_model?
    File.exists? @model_path
  end

  def has_archive?
    File.exists? @archive_path
  end

  def get_archive!
    @archive = Archive.new(@original, @archive_path, make_client).sync
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
      p "#{field} = #{send(field)}"
      send(field).nil? || send(field).empty?
    }
  end
end
