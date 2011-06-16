(function() {
  var API_URI, Quarter, Term, badJSON, clients, file, goodJSON, http, quarters, redis, rest, server, static, sys, url, _;
  var __bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; };
  API_URI = "http://api.thriftdb.com/api.hnsearch.com/items/_search";
  _ = require("underscore");
  sys = require("sys");
  http = require("http");
  rest = require("restler");
  url = require("url");
  static = require("node-static");
  file = new static.Server("./public");
  redis = require("redis").createClient();
  Quarter = (function() {
    function Quarter(id, start, end) {
      this.id = id;
      this.start = start;
      this.end = end;
    }
    Quarter.prototype.queryString = function() {
      return "create_ts:[" + this.start + " TO " + this.end + "]";
    };
    return Quarter;
  })();
  Term = (function() {
    function Term(term, quarter, client, last) {
      this.term = term;
      this.quarter = quarter;
      this.client = client;
      this.last = last != null ? last : false;
    }
    Term.prototype.getHits = function() {
      sys.puts("getHits: " + this.term + " " + this.quarter.id);
      return redis.hget("hntrends:term:" + this.term, this.quarter.id, __bind(function(err, res) {
        if (res) {
          this.hits = res;
          return this.storeHitsForClient();
        } else {
          return this.getRemoteHits();
        }
      }, this));
    };
    Term.prototype.getRemoteHits = function() {
      var options, request;
      sys.puts("getRemoteHits: " + this.term + " " + this.quarter.id);
      options = {
        query: {
          "q": this.term,
          "filter[queries][]": this.quarter.queryString()
        }
      };
      request = rest.get(API_URI, options);
      request.on("error", function(data, response) {
        return sys.puts("api error: " + data);
      });
      return request.on("complete", __bind(function(data) {
        this.hits = JSON.parse(data).hits;
        redis.hset("hntrends:term:" + this.term, this.quarter.id, this.hits);
        return this.storeHitsForClient();
      }, this));
    };
    Term.prototype.storeHitsForClient = function() {
      return this.client.termHits.push({
        term: this.term,
        quarter: this.quarter.id,
        hits: this.hits,
        last: this.last
      });
    };
    Term.prototype.sendTrend = function() {
      return this.client.send({
        "term": this.term,
        "quarter": this.quarter.id,
        "hits": this.hits
      });
    };
    return Term;
  })();
  quarters = [new Quarter("2007-1", "2007-01-01T00:00:00Z", "2007-03-31T23:59:59Z"), new Quarter("2007-2", "2007-04-01T00:00:00Z", "2007-06-30T23:59:59Z"), new Quarter("2007-3", "2007-07-01T00:00:00Z", "2007-09-30T23:59:59Z"), new Quarter("2007-4", "2007-10-01T00:00:00Z", "2007-12-31T23:59:59Z"), new Quarter("2008-1", "2008-01-01T00:00:00Z", "2008-03-31T23:59:59Z"), new Quarter("2008-2", "2008-04-01T00:00:00Z", "2008-06-30T23:59:59Z"), new Quarter("2008-3", "2008-07-01T00:00:00Z", "2008-09-30T23:59:59Z"), new Quarter("2008-4", "2008-10-01T00:00:00Z", "2008-12-31T23:59:59Z"), new Quarter("2009-1", "2009-01-01T00:00:00Z", "2009-03-31T23:59:59Z"), new Quarter("2009-2", "2009-04-01T00:00:00Z", "2009-06-30T23:59:59Z"), new Quarter("2009-3", "2009-07-01T00:00:00Z", "2009-09-30T23:59:59Z"), new Quarter("2009-4", "2009-10-01T00:00:00Z", "2009-12-31T23:59:59Z"), new Quarter("2010-1", "2010-01-01T00:00:00Z", "2010-03-31T23:59:59Z"), new Quarter("2010-2", "2010-04-01T00:00:00Z", "2010-06-30T23:59:59Z"), new Quarter("2010-3", "2010-07-01T00:00:00Z", "2010-09-30T23:59:59Z"), new Quarter("2010-4", "2010-10-01T00:00:00Z", "2010-12-31T23:59:59Z"), new Quarter("2011-1", "2011-01-01T00:00:00Z", "2011-03-31T23:59:59Z")];
  clients = {};
  server = http.createServer(function(request, response) {
    var client, clientId, deets, more, terms;
    deets = url.parse(request.url, true);
    switch (deets.pathname) {
      case "/terms":
        if (deets.query.q) {
          terms = deets.query.q.split(",");
          clientId = _.uniqueId();
          clients[clientId] = {
            termHits: [],
            complete: false
          };
          _.each(terms, function(term) {
            return redis.zincrby("hntrends:queries", 1, term);
          });
          _.each(quarters, function(quarter, i) {
            return _.each(terms, function(term, j) {
              if ((i + 1) === quarters.length && (j + 1) === terms.length) {
                return new Term(term, quarter, clients[clientId], true).getHits();
              } else {
                return new Term(term, quarter, clients[clientId]).getHits();
              }
            });
          });
          return goodJSON(response, {
            clientId: clientId
          });
        } else {
          return badJSON(response, {
            status: "missing required terms"
          });
        }
        break;
      case "/more":
        client = clients[deets.query.clientId];
        if (client) {
          more = client.termHits.shift();
          if (more) {
            return goodJSON(response, more);
          } else {
            return goodJSON(response, {
              noop: true
            });
          }
        } else {
          return badJSON(response, {
            status: "missing or unknown client id"
          });
        }
        break;
      default:
        return file.serve(request, response);
    }
  });
  server.listen(3000);
  goodJSON = function(response, object) {
    response.writeHead(200, {
      "Content-Type": "text/plain"
    });
    return response.end(JSON.stringify(object));
  };
  badJSON = function(response, object) {
    response.writeHead(422, {
      "Content-Type": "text/plain"
    });
    return response.end(JSON.stringify(object));
  };
}).call(this);
