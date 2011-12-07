API_URI = "http://api.thriftdb.com/api.hnsearch.com/items/_search"

_      = require "underscore"
sys    = require "sys"
http   = require "http"
rest   = require "restler"
url    = require "url"
static = require "node-static"
file   = new static.Server("./public")

if process.env.REDISTOGO_URL
  rtg   = url.parse process.env.REDISTOGO_URL
  redis = require("redis").createClient(rtg.port, rtg.hostname)
  redis.auth rtg.auth.split(":")[1]
else
  redis = require("redis").createClient()

unixTime = (date) ->
  Math.round(date.getTime() / 1000)

class Quarter
  constructor: (@id, @name, @start, @end, @totalHits) ->

  queryString: ->
    "create_ts:[#{@start} TO #{@end}]"

  factor: (mostRecent) ->
    mostRecent.totalHits / @totalHits

class Term
  constructor: (@term, @quarter, @client, @last = false) ->

  getHits: ->
    redis.hget "hntrends:term:#{@term}", @quarter.id, (err, res) =>
      if res
        @hits = res
        @storeHitsForClient()
      else
        @getRemoteHits()

  getRemoteHits: ->
    options = {
      query: {
        "q": @term
        "filter[queries][]": @quarter.queryString()
        "limit": 0
        "weights[title]": 1.0,
        "weights[text]": 1,0
      }
    }

    request = rest.get(API_URI, options)

    request.on "error", (data, response) ->
      sys.puts "api error: " + data

    request.on "complete", (data) =>
      @hits = JSON.parse(data).hits
      key = "hntrends:term:#{@term}"
      redis.hset key, @quarter.id, @hits
      redis.expireat key, unixTime(new Date("2012-01-01 GMT"))
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
# totalHits: http://api.thriftdb.com/api.hnsearch.com/items/_search?filter[queries][]=create_ts:[2011-04-01T00:00:00Z%20TO%202011-06-30T23:59:59Z]&limit=0
quarters = [
  new Quarter "2007-1", "2007",    "2007-01-01T00:00:00Z", "2007-03-31T23:59:59Z", 7683
  new Quarter "2007-2", "Q2 2007", "2007-04-01T00:00:00Z", "2007-06-30T23:59:59Z", 22974
  new Quarter "2007-3", "Q3 2007", "2007-07-01T00:00:00Z", "2007-09-30T23:59:59Z", 28431
  new Quarter "2007-4", "Q4 2007", "2007-10-01T00:00:00Z", "2007-12-31T23:59:59Z", 31325
  new Quarter "2008-1", "2008",    "2008-01-01T00:00:00Z", "2008-03-31T23:59:59Z", 54923
  new Quarter "2008-2", "Q2 2008", "2008-04-01T00:00:00Z", "2008-06-30T23:59:59Z", 76839
  new Quarter "2008-3", "Q3 2008", "2008-07-01T00:00:00Z", "2008-09-30T23:59:59Z", 81093
  new Quarter "2008-4", "Q4 2008", "2008-10-01T00:00:00Z", "2008-12-31T23:59:59Z", 89281
  new Quarter "2009-1", "2009",    "2009-01-01T00:00:00Z", "2009-03-31T23:59:59Z", 116194
  new Quarter "2009-2", "Q2 2009", "2009-04-01T00:00:00Z", "2009-06-30T23:59:59Z", 129283
  new Quarter "2009-3", "Q3 2009", "2009-07-01T00:00:00Z", "2009-09-30T23:59:59Z", 159930
  new Quarter "2009-4", "Q4 2009", "2009-10-01T00:00:00Z", "2009-12-31T23:59:59Z", 157422
  new Quarter "2010-1", "2010",    "2010-01-01T00:00:00Z", "2010-03-31T23:59:59Z", 192754
  new Quarter "2010-2", "Q2 2010", "2010-04-01T00:00:00Z", "2010-06-30T23:59:59Z", 225210
  new Quarter "2010-3", "Q3 2010", "2010-07-01T00:00:00Z", "2010-09-30T23:59:59Z", 248110
  new Quarter "2010-4", "Q4 2010", "2010-10-01T00:00:00Z", "2010-12-31T23:59:59Z", 288470
  new Quarter "2011-1", "2011",    "2011-01-01T00:00:00Z", "2011-03-31T23:59:59Z", 311190
  new Quarter "2011-2", "Q2 2011", "2011-04-01T00:00:00Z", "2011-06-30T23:59:59Z", 290672
  new Quarter "2011-3", "Q3 2011", "2011-07-01T00:00:00Z", "2011-09-30T23:59:59Z", 298689
  # new Quarter "2011-4", "Q4 2011", "2011-10-01T00:00:00Z", "2011-12-31T23:59:59Z", UNKNOWN
]

clients = {}

respondWithJSON = (response, code, object) ->
  response.writeHead code, {"Content-Type": "text/plain"}
  response.end JSON.stringify(object)

purgeOldClients = ->
  now = new Date()
  _.each clients, (object, key) ->
    if now - object.timestamp > 30 * 1000
      delete clients[key]

server = http.createServer (request, response) ->
  deets = url.parse(request.url, true)
  switch deets.pathname
    when "/quarters"
      quartersInfo = _.map quarters, (q) ->
        {
          name: q.name
        factor: q.factor(_.last(quarters))
        }
      respondWithJSON response, 200, quartersInfo
    when "/terms"
      if deets.query.q
        sys.puts "terms request: #{request.url}"
        terms    = deets.query.q.split(",")
        clientId = _.uniqueId()

        # initialize a new client object
        clients[clientId] = {termHits: [], complete: false, timestamp: new Date()}

        # store the term queried for later analysis
        _.each terms, (term) ->
          redis.zincrby "hntrends:queries", 1, term

        # loop the terms for each quarter and get hits
        _.each quarters, (quarter, i) ->
          _.each terms, (term, j) ->
            # special case for the last term in the last quarter
            if (i + 1) == quarters.length && (j + 1) == terms.length
              new Term(term, quarter, clients[clientId], true).getHits()
            else
              new Term(term, quarter, clients[clientId]).getHits()

        # send the id back to browser for future requests
        respondWithJSON response, 200, {clientId: clientId}
      else
        sys.puts "bad request: #{request.url}"
        respondWithJSON response, 422, {status: "missing required terms"}
    when "/more"
      client = clients[deets.query.clientId]
      if client
        client.timestamp = new Date()
        more = client.termHits.shift()
        if more
          respondWithJSON response, 200, more
        else
          respondWithJSON response, 200, {noop: true}
      else
        sys.puts "bad request: #{request.url}"
        respondWithJSON response, 422, {status: "missing or unknown client id"}
    else
      file.serve request, response

port = process.env.PORT || 3000
server.listen port, ->
  sys.puts "listening on port #{port}..."

setInterval purgeOldClients, 3000
