#!/usr/bin/env ruby

require 'twitter_ebooks'

#monkeypatch in a special csv consumer
module Ebooks
  class Model
    def consume(path)
      content = File.read(path, :encoding => 'utf-8')
      log "Reading special CSV corpus from #{path}"
      content = CSV.parse(content)
      header = content.shift
      text_col = header.index('text')
      lines = content.map do |tweet|
        tweet[text_col]
      end

      statements = []

      #instead of consume_lines we do this
      lines.each do |l|
        #remove short or blank lines
        next if !l
        next if l.length <= 2
        #remove too long for tweet lines
        next if l.length > 140
        #normalize all as statements
        statements << NLP.normalize(l)
      end

      text = statements.join("\n")
      lines = nil; statements = nil; mentions = nil;

      log "tokenfiyinggg"
      @sentences = mass_tikify(text)
      @mentions = []
      log "keyworrrdingggg"
      @keywords = NLP.keywords(text).top(200).map(&:to_s)

      self
    end
  end
end

#run this script to consume import.csv
Ebooks::Model.consume('corpus/zebrapedia.csv').save('model/zebrapedia.model')
