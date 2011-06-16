(function() {
  var HNTrends;
  var __bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; };
  HNTrends = (function() {
    function HNTrends(pendingPlots, maxY) {
      this.pendingPlots = pendingPlots != null ? pendingPlots : [];
      this.maxY = maxY != null ? maxY : 100;
      this.plotPending = __bind(this.plotPending, this);
      this.handleMessage = __bind(this.handleMessage, this);
      this.initSocket();
      this.initTerms();
    }
    HNTrends.prototype.initSocket = function() {
      this.socket = new io.Socket;
      this.socket.connect();
      return this.socket.on("message", this.handleMessage);
    };
    HNTrends.prototype.initTerms = function() {
      var interval, termList, terms;
      terms = this.getParam("q");
      if (terms.length) {
        $("input[type=text]:first").val(terms);
        termList = terms.split(",");
        this.terms = _.map(termList, function(t) {
          return t.trim().toLowerCase();
        });
        this.terms = _.first(this.terms, 5);
        this.initChart();
        this.submitTerms();
        interval = (function() {
          switch (this.terms.length) {
            case 1:
              return 450;
            case 2:
              return 250;
            case 3:
              return 200;
            default:
              return 150;
          }
        }).call(this);
        return setInterval(this.plotPending, interval);
      }
    };
    HNTrends.prototype.initChart = function() {
      var options;
      $("#examples").hide();
      options = {
        colors: ["#FFFFFF", "#E90000", "#FFCC00", "#6699FF", "#8C1A99", "#99FF00"],
        chart: {
          renderTo: "chart",
          ignoreHiddenSeries: false
        },
        title: null,
        legend: {
          itemHiddenStyle: {
            color: "#FFF"
          },
          itemStyle: {
            color: "#666"
          },
          borderWidth: 0,
          floating: true,
          layout: "vertical",
          align: "left",
          x: 70,
          verticalAlign: "top",
          y: -7
        },
        xAxis: {
          categories: ["2007", "Q2 2007", "Q3 2007", "Q4 2007", "2008", "Q2 2008", "Q3 2008", "Q4 2008", "2009", "Q2 2009", "Q3 2009", "Q4 2009", "2010", "Q2 2010", "Q3 2010", "Q4 2010", "2011"],
          labels: {
            step: 4
          }
        },
        yAxis: {
          title: {
            text: "Hacker Mentions",
            style: {
              color: "#ff6600"
            }
          },
          labels: {
            align: "left",
            x: 0,
            y: -2
          },
          min: 0
        },
        plotOptions: {
          line: {
            lineWidth: 4,
            states: {
              hover: {
                lineWidth: 5
              }
            },
            marker: {
              enabled: false,
              states: {
                hover: {
                  enabled: true,
                  symbol: "circle",
                  radius: 5,
                  lineWidth: 1
                }
              }
            }
          }
        },
        series: [
          {
            name: "oh hai!",
            id: "skeleton",
            data: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
          }
        ]
      };
      _.each(this.terms, function(term) {
        return options.series.push({
          name: term,
          id: term
        });
      });
      this.chart = new Highcharts.Chart(options);
      return this.chart.get("skeleton").hide();
    };
    HNTrends.prototype.submitTerms = function(terms) {
      return this.socket.send(this.terms);
    };
    HNTrends.prototype.getParam = function(name) {
      var regex, results;
      name = name.replace(/[\[]/, "\\\[").replace(/[\]]/, "\\\]");
      regex = new RegExp("[\\?&]" + name + "=([^&#]*)");
      results = regex.exec(window.location.href);
      if (!results) {
        return "";
      }
      return decodeURIComponent(results[1].replace(/\+/g, " "));
    };
    HNTrends.prototype.handleMessage = function(message) {
      message.hits = parseInt(message.hits);
      if (message.hits > this.maxY) {
        this.maxY = message.hits;
        this.chart.yAxis[0].setExtremes(0, this.maxY, true, false);
      }
      return this.pendingPlots.push(message);
    };
    HNTrends.prototype.plotPending = function() {
      var message;
      message = this.pendingPlots.shift();
      if (!message) {
        return;
      }
      return this.chart.get(message.term).addPoint(message.hits);
    };
    return HNTrends;
  })();
  $(function() {
    return window.HNTrends = new HNTrends();
  });
}).call(this);
