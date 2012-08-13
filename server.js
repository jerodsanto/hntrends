(function() {
  var API_URI, Quarter, Term, clients, file, http, moment, port, purgeOldClients, quarters, redis, refreshQuarters, respondWithJSON, rest, rtg, server, static, unixTime, url, util, _;

  API_URI = "http://api.thriftdb.com/api.hnsearch.com/items/_search";

  _ = require("underscore");

  util = require("util");

  http = require("http");

  rest = require("restler");

  url = require("url");

  static = require("node-static");

  moment = require("moment");

  file = new static.Server("./public");

  quarters = [];

  clients = {};

  if (process.env.REDISTOGO_URL) {
    rtg = url.parse(process.env.REDISTOGO_URL);
    redis = require("redis").createClient(rtg.port, rtg.hostname);
    redis.auth(rtg.auth.split(":")[1]);
  } else {
    redis = require("redis").createClient();
  }

  unixTime = function(date) {
    return Math.round(date.getTime() / 1000);
  };

  Term = (function() {

    function Term(term, quarter, client, last) {
      this.term = term;
      this.quarter = quarter;
      this.client = client;
      this.last = last != null ? last : false;
    }

    Term.prototype.getHits = function() {
      var _this = this;
      return redis.hget("hntrends:term:" + this.term, this.quarter.id, function(err, res) {
        if (res) {
          _this.hits = res;
          return _this.storeHitsForClient();
        } else {
          return _this.getRemoteHits();
        }
      });
    };

    Term.prototype.getRemoteHits = function() {
      var options, request;
      var _this = this;
      options = {
        query: {
          "q": this.term,
          "filter[queries][]": this.quarter.queryString(),
          "limit": 0,
          "weights[title]": 1.0,
          "weights[text]": 1,
          0: 0
        }
      };
      request = rest.get(API_URI, options);
      request.on("error", function(data, response) {
        return util.puts("api error: " + data);
      });
      return request.on("complete", function(data) {
        var key;
        _this.hits = JSON.parse(data).hits;
        key = "hntrends:term:" + _this.term;
        redis.hset(key, _this.quarter.id, _this.hits);
        redis.expireat(key, unixTime(new Date("2012-01-01 GMT")));
        return _this.storeHitsForClient();
      });
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

  Quarter = (function() {

    Quarter.fromMoment = function(moment) {
      var quarter;
      quarter = (function() {
        switch (moment.month()) {
          case 0:
          case 1:
          case 2:
            return 1;
          case 3:
          case 4:
          case 5:
            return 2;
          case 6:
          case 7:
          case 8:
            return 3;
          case 9:
          case 10:
          case 11:
            return 4;
        }
      })();
      return new this(moment.year(), quarter);
    };

    function Quarter(year, quarter) {
      this.year = year;
      this.quarter = quarter;
      this.id = "" + this.year + "-" + this.quarter;
      this.redisKey = "hntrends:quarters:" + this.id;
      this.getTotalHits();
    }

    Quarter.prototype.nextQuarter = function() {
      if (this.quarter === 4) {
        return new Quarter(this.year + 1, 1);
      } else {
        return new Quarter(this.year, this.quarter + 1);
      }
    };

    Quarter.prototype.queryString = function() {
      var e, s;
      s = this.start();
      e = this.end();
      return "create_ts:[" + s + " TO " + e + "]";
    };

    Quarter.prototype.factor = function(mostRecent) {
      return mostRecent.totalHits / this.totalHits;
    };

    Quarter.prototype.name = function() {
      if (this.quarter === 1) {
        return "" + this.year;
      } else {
        return "Q" + this.quarter + " " + this.year;
      }
    };

    Quarter.prototype.start = function() {
      var date;
      date = (function() {
        switch (this.quarter) {
          case 1:
            return "01-01";
          case 2:
            return "04-01";
          case 3:
            return "07-01";
          case 4:
            return "10-01";
        }
      }).call(this);
      return "" + this.year + "-" + date + "T00:00:00Z";
    };

    Quarter.prototype.end = function() {
      var date;
      date = (function() {
        switch (this.quarter) {
          case 1:
            return "03-31";
          case 2:
            return "06-30";
          case 3:
            return "09-30";
          case 4:
            return "12-31";
        }
      }).call(this);
      return "" + this.year + "-" + date + "T23:59:59Z";
    };

    Quarter.prototype.getTotalHits = function() {
      var _this = this;
      return redis.get(this.redisKey, function(err, res) {
        if (res) {
          _this.totalHits = res;
          return util.puts("Redis hits for quarter: " + _this.id + " is " + _this.totalHits);
        } else {
          return _this.getRemoteTotalHits();
        }
      });
    };

    Quarter.prototype.getRemoteTotalHits = function() {
      var options, request;
      var _this = this;
      options = {
        query: {
          "filter[queries][]": this.queryString(),
          "limit": 0
        }
      };
      request = rest.get(API_URI, options);
      request.on("error", function(data, response) {
        return util.puts("api error: " + data);
      });
      return request.on("complete", function(data) {
        _this.totalHits = JSON.parse(data).hits;
        util.puts("Remote hits for quarter: " + _this.id + " is " + _this.totalHits);
        return redis.set(_this.redisKey, _this.totalHits);
      });
    };

    return Quarter;

  })();

  refreshQuarters = function(refreshToQuarter) {
    var currentQuarter, nextQuarter, _results;
    util.puts("refreshing quarters");
    if (quarters.length) {
      currentQuarter = _.last(quarters);
    } else {
      currentQuarter = new Quarter(2007, 1);
      quarters = [currentQuarter];
    }
    _results = [];
    while (currentQuarter.id !== refreshToQuarter.id) {
      nextQuarter = currentQuarter.nextQuarter();
      quarters.push(nextQuarter);
      _results.push(currentQuarter = nextQuarter);
    }
    return _results;
  };

  respondWithJSON = function(response, code, object) {
    response.writeHead(code, {
      "Content-Type": "text/plain"
    });
    return response.end(JSON.stringify(object));
  };

  purgeOldClients = function() {
    var now;
    now = new Date();
    return _.each(clients, function(object, key) {
      if (now - object.timestamp > 30 * 1000) return delete clients[key];
    });
  };

  refreshQuarters(Quarter.fromMoment(moment()));

  server = http.createServer(function(request, response) {
    var client, clientId, deets, more, quartersInfo, terms;
    deets = url.parse(request.url, true);
    switch (deets.pathname) {
      case "/quarters":
        refreshQuarters(Quarter.fromMoment(moment()));
        quartersInfo = _.map(quarters, function(q) {
          return {
            name: q.name(),
            factor: q.factor(_.last(quarters))
          };
        });
        return respondWithJSON(response, 200, quartersInfo);
      case "/terms":
        if (deets.query.q) {
          util.puts("terms request: " + request.url);
          terms = deets.query.q.split(",");
          clientId = _.uniqueId();
          clients[clientId] = {
            termHits: [],
            complete: false,
            timestamp: new Date()
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
          return respondWithJSON(response, 200, {
            clientId: clientId
          });
        } else {
          util.puts("bad request: " + request.url);
          return respondWithJSON(response, 422, {
            status: "missing required terms"
          });
        }
        break;
      case "/more":
        client = clients[deets.query.clientId];
        if (client) {
          client.timestamp = new Date();
          more = client.termHits.shift();
          if (more) {
            return respondWithJSON(response, 200, more);
          } else {
            return respondWithJSON(response, 200, {
              noop: true
            });
          }
        } else {
          util.puts("bad request: " + request.url);
          return respondWithJSON(response, 422, {
            status: "missing or unknown client id"
          });
        }
        break;
      default:
        return file.serve(request, response);
    }
  });

  port = process.env.PORT || 3000;

  server.listen(port, function() {
    return util.puts("listening on port " + port + "...");
  });

  setInterval(purgeOldClients, 3000);

}).call(this);
