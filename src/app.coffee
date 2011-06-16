API_URI = "http://api.thriftdb.com/api.hnsearch.com/items/_search"

_      = require "underscore"
sys    = require "sys"
http   = require "http"
rest   = require "restler"
url    = require "url"
qs     = require "querystring"
static = require "node-static"
io     = require "socket.io"
file   = new static.Server("./public")
redis  = require("redis").createClient()

class Quarter
  constructor: (@id, @start, @end) ->

  queryString: ->
    "create_ts:[#{@start} TO #{@end}]"

class Term
  constructor: (@term, @quarter, @client) ->

  getTrend: ->
    sys.puts "getTrend: #{@term} #{@quarter.id}"
    redis.hget "hntrends:term:#{@term}", @quarter.id, (err, res) =>
      if res
        @hits = res
        @sendTrend()
      else
        @getRemoteTrend()

  getRemoteTrend: ->
    sys.puts "getRemoteTrend: #{@term} #{@quarter.id}"
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
      @sendTrend()

  sendTrend: ->
    @client.send {
      "term": @term, "quarter": @quarter.id, "hits": @hits
    }

class FakeClient
  send: ->
    sys.puts

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

server = http.createServer (request, response) ->
  request.addListener "end", ->
    file.serve request, response

server.listen 3000

socket = io.listen server
socket.on "connection", (client) ->
  client.on "message", (message) ->
    termList = message.split(",")
    _.each termList, (term) ->
      redis.zincrby "hntrends:queries", 1, term
    _.each quarters, (quarter) ->
      _.each termList, (term) ->
        new Term(term, quarter, client).getTrend()
