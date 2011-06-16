API_URI = "http://api.thriftdb.com/api.hnsearch.com/items/_search"

_      = require "underscore"
sys    = require "sys"
http   = require "http"
rest   = require "restler"
url    = require "url"
static = require "node-static"
file   = new static.Server("./public")
redis  = require("redis").createClient()

class Quarter
  constructor: (@id, @start, @end) ->

  queryString: ->
    "create_ts:[#{@start} TO #{@end}]"

class Term
  constructor: (@term, @quarter, @client, @last = false) ->

  getHits: ->
    sys.puts "getHits: #{@term} #{@quarter.id}"
    redis.hget "hntrends:term:#{@term}", @quarter.id, (err, res) =>
      if res
        @hits = res
        @storeHitsForClient()
      else
        @getRemoteHits()

  getRemoteHits: ->
    sys.puts "getRemoteHits: #{@term} #{@quarter.id}"
    options = {
      query: {
        "q": @term, "filter[queries][]": @quarter.queryString()
      }
    }

    request = rest.get(API_URI, options)

    request.on "error", (data, response) ->
      sys.puts "api error: " + data

    request.on "complete", (data) =>
      @hits = JSON.parse(data).hits
      redis.hset "hntrends:term:#{@term}", @quarter.id, @hits
      @storeHitsForClient()

  storeHitsForClient: ->
    @client.termHits.push {
      term: @term
      quarter: @quarter.id
      hits: @hits
      last: @last
    }

  sendTrend: ->
    @client.send {
      "term": @term, "quarter": @quarter.id, "hits": @hits
    }

# TODO - make this dynamic based on today's quarter
quarters = [
  new Quarter "2007-1", "2007-01-01T00:00:00Z", "2007-03-31T23:59:59Z"
  new Quarter "2007-2", "2007-04-01T00:00:00Z", "2007-06-30T23:59:59Z"
  new Quarter "2007-3", "2007-07-01T00:00:00Z", "2007-09-30T23:59:59Z"
  new Quarter "2007-4", "2007-10-01T00:00:00Z", "2007-12-31T23:59:59Z"
  new Quarter "2008-1", "2008-01-01T00:00:00Z", "2008-03-31T23:59:59Z"
  new Quarter "2008-2", "2008-04-01T00:00:00Z", "2008-06-30T23:59:59Z"
  new Quarter "2008-3", "2008-07-01T00:00:00Z", "2008-09-30T23:59:59Z"
  new Quarter "2008-4", "2008-10-01T00:00:00Z", "2008-12-31T23:59:59Z"
  new Quarter "2009-1", "2009-01-01T00:00:00Z", "2009-03-31T23:59:59Z"
  new Quarter "2009-2", "2009-04-01T00:00:00Z", "2009-06-30T23:59:59Z"
  new Quarter "2009-3", "2009-07-01T00:00:00Z", "2009-09-30T23:59:59Z"
  new Quarter "2009-4", "2009-10-01T00:00:00Z", "2009-12-31T23:59:59Z"
  new Quarter "2010-1", "2010-01-01T00:00:00Z", "2010-03-31T23:59:59Z"
  new Quarter "2010-2", "2010-04-01T00:00:00Z", "2010-06-30T23:59:59Z"
  new Quarter "2010-3", "2010-07-01T00:00:00Z", "2010-09-30T23:59:59Z"
  new Quarter "2010-4", "2010-10-01T00:00:00Z", "2010-12-31T23:59:59Z"
  new Quarter "2011-1", "2011-01-01T00:00:00Z", "2011-03-31T23:59:59Z"
]

clients = {}

server = http.createServer (request, response) ->
  deets = url.parse(request.url, true)
  switch deets.pathname
    when "/terms"
      if deets.query.q
        terms    = deets.query.q.split(",")
        clientId = _.uniqueId()

        # initialize a new client object
        clients[clientId] = {termHits: [], complete: false}

        # store the term queried for later analysis
        _.each terms, (term) ->
          redis.zincrby "hntrends:queries", 1, term

        # loop the terms for each quarter and get hits
        _.each quarters, (quarter, i) ->
          _.each terms, (term, j) ->
            # special case for the last term in the last quarter
            if (i + 1) == quarters.length && (j + 1) == terms.length
              sys.puts "new term: last"
              new Term(term, quarter, clients[clientId], true).getHits()
            else
              sys.puts "new term"
              new Term(term, quarter, clients[clientId]).getHits()

        # send the id back to browser for future requests
        goodJSON response, {clientId: clientId}
      else
        # TODO - respond poorly
        sys.puts "query string not defined"
    when "/more"
      client = clients[deets.query.clientId]
      if client
        more = client.termHits.shift()
        if more
          goodJSON response, more
        else
          goodJSON response, {noop: true}
      else
        sys.puts "client id not defined"
    else
      file.serve request, response

server.listen 3000

goodJSON = (response, object) ->
  response.writeHead 200, {"Content-Type": "text/plain"}
  response.end JSON.stringify(object)
