API_URI = "http://api.thriftdb.com/api.hnsearch.com/items/_search"

_      = require "underscore"
util   = require "util"
http   = require "http"
rest   = require "restler"
url    = require "url"
moment = require "moment"
statik = require("node-static")
file   = new statik.Server "./public"

quarters = []
clients  = {}

if process.env.REDISTOGO_URL
    rtg   = url.parse process.env.REDISTOGO_URL
    redis = require("redis").createClient(rtg.port, rtg.hostname)
    redis.auth rtg.auth.split(":")[1]
else
    redis = require("redis").createClient()

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
        options =
            query:
                "q": @term
                "filter[queries][]": @quarter.queryString()
                "limit": 0
                "weights[title]": 1.0
                "weights[text]": 1.0

        request = rest.get API_URI, options

        request.on "error", (data, response) ->
            util.puts "api error: #{data}"

        request.on "complete", (data) =>
            @hits = JSON.parse(data).hits
            key = "hntrends:term:#{@term}"
            redis.hset key, @quarter.id, @hits
            redis.expireat key, moment().add("years", 1).unix()
            @storeHitsForClient()

    getTopStories: (callback) ->
        options =
            query:
                "q": @term
                "filter[queries][]": @quarter.queryString()
                "filter[fields][type][]": "submission"
                "sortby": "points desc"
                "limit": 10

        request = rest.get API_URI, options

        request.on "error", (data, response) ->
            util.puts "api error: #{data}"

        request.on "complete", (data) ->
            stories = _.map(JSON.parse(data).results, (r) -> r.item)
            callback stories

    storeHitsForClient: ->
        @client.termHits.push
            term: @term
            quarter: @quarter.id
            hits: @hits
            last: @last

class Quarter
    @fromMoment: (moment) ->
        # we always want to go back one quarter from the current moment
        [year, quarter] = switch moment.month()
            when 0, 1, 2   then [moment.year() - 1, 4]
            when 3, 4, 5   then [moment.year(), 1]
            when 6, 7, 8   then [moment.year(), 2]
            when 9, 10, 11 then [moment.year(), 3]

        new this year, quarter

    constructor: (@year, @quarter) ->
        @id = "#{@year}-#{@quarter}"
        @redisKey = "hntrends:quarters:#{@id}"
        @getTotalHits()

    nextQuarter: ->
        if @quarter == 4
            new Quarter @year + 1, 1
        else
            new Quarter @year, @quarter + 1

    queryString: ->
        "create_ts:[" + @start() + " TO " + @end() + "]"

    factor: (mostRecent) ->
        mostRecent.totalHits / @totalHits

    name: ->
        "Q#{@quarter} #{@year}"

    start: ->
        date = switch @quarter
            when 1 then "01-01"
            when 2 then "04-01"
            when 3 then "07-01"
            when 4 then "10-01"
        "#{@year}-#{date}T00:00:00Z"

    end: ->
        date = switch @quarter
            when 1 then "03-31"
            when 2 then "06-30"
            when 3 then "09-30"
            when 4 then "12-31"
        "#{@year}-#{date}T23:59:59Z"

    getTotalHits: ->
        redis.get @redisKey, (err, res) =>
            if res
                @totalHits = res
            else
                @getRemoteTotalHits()

    getRemoteTotalHits: ->
        options = {
            query: {
                "filter[queries][]": @queryString()
                "limit": 0
            }
        }

        request = rest.get(API_URI, options)

        request.on "error", (data, response) ->
            util.puts "api error: " + data

        request.on "complete", (data) =>
            @totalHits = JSON.parse(data).hits
            redis.set @redisKey, @totalHits

refreshQuarters = (refreshToQuarter) ->
    if quarters.length
        currentQuarter = _.last quarters
    else
        currentQuarter = new Quarter 2007, 1
        quarters = [currentQuarter]

    while currentQuarter.id != refreshToQuarter.id
        nextQuarter = currentQuarter.nextQuarter()
        quarters.push nextQuarter
        currentQuarter = nextQuarter

respondWithJSON = (response, code, object) ->
    response.writeHead code, {"Content-Type": "text/plain"}
    response.end JSON.stringify(object)

purgeOldClients = ->
    now = new Date()
    _.each clients, (object, key) ->
        if now - object.timestamp > 30 * 1000
            delete clients[key]

# refresh once on boot to populate the quarters array
refreshQuarters Quarter.fromMoment(moment())

server = http.createServer (request, response) ->
    deets = url.parse(request.url, true)
    switch deets.pathname
        when "/quarters"
            refreshQuarters Quarter.fromMoment(moment())

            quartersInfo = _.map quarters, (q) ->
                {
                    name: q.name()
                    factor: q.factor(_.last(quarters))
                }
            respondWithJSON response, 200, quartersInfo
        when "/terms"
            if deets.query.q
                util.puts "terms request: #{request.url}"
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
                util.puts "bad request: #{request.url}"
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
                util.puts "bad request: #{request.url}"
                respondWithJSON response, 422, {status: "missing or unknown client id"}
        when "/stories"
            client = clients[deets.query.clientId]
            if client && deets.query.term && deets.query.quarter
                util.puts "stories request: #{request.url}"
                quarter = quarters[deets.query.quarter]
                term = new Term deets.query.term, quarter, client
                term.getTopStories (stories) ->
                    respondWithJSON response, 200, stories
            else
                util.puts "bad request: #{request.url}"
                respondWithJSON response, 422, {status: "missing required params"}
        else
            file.serve request, response

port = process.env.PORT || 3000
server.listen port, ->
    util.puts "listening on port #{port}..."

setInterval purgeOldClients, 3000
