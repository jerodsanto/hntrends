(function() {
  var HNTrends;
  var __bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; };

  $.ajaxSetup({
    cache: false
  });

  HNTrends = (function() {

    function HNTrends(pendingPlots, maxY, clientId) {
      this.pendingPlots = pendingPlots != null ? pendingPlots : [];
      this.maxY = maxY != null ? maxY : 100;
      this.clientId = clientId;
      this.plotPending = __bind(this.plotPending, this);
      this.initTerms();
    }

    HNTrends.prototype.initTerms = function() {
      var input, interval, termList, terms;
      var _this = this;
      terms = this.getParam("q");
      input = $("input[type=text]:first");
      if (terms.length) {
        input.val(terms);
        $(".twitter-share-button").attr("data-url", "" + window.location.host + "/q=" + terms);
        termList = terms.split(",");
        this.terms = _.map(termList, function(t) {
          return $.trim(t.toLowerCase());
        });
        this.terms = _.first(this.terms, 5);
        interval = (function() {
          switch (this.terms.length) {
            case 1:
              return 450;
            case 2:
              return 300;
            default:
              return 250;
          }
        }).call(this);
        setTimeout(function() {
          return _this.interval = setInterval(_this.plotPending, interval);
        }, 500);
        return this.getQuarters();
      } else {
        return input.focus();
      }
    };

    HNTrends.prototype.getQuarters = function() {
      var _this = this;
      return $.getJSON("/quarters", function(data) {
        _this.quarters = data;
        _this.initChart();
        return _this.getTerms();
      });
    };

    HNTrends.prototype.initChart = function() {
      var nullFill, options;
      $("#examples").hide();
      options = {
        colors: ["#FF0000", "#FFCC00", "#6699FF", "#8C1A99", "#99FF00"],
        chart: {
          renderTo: "chart"
        },
        title: null,
        tooltip: {
          crosshairs: true,
          formatter: function() {
            var a, b;
            a = Highcharts.numberFormat(this.y, 0, ",");
            b = Highcharts.numberFormat(this.point.actual, 0, ",");
            return "<b>" + this.series.name + "</b>in " + this.x + ": " + a + " adjusted (" + b + " actual)";
          }
        },
        legend: {
          itemStyle: {
            color: "#666"
          },
          borderWidth: 0,
          floating: true,
          layout: "vertical",
          align: "left",
          x: 70,
          verticalAlign: "top",
          y: 0
        },
        xAxis: {
          categories: _.map(this.quarters, function(q) {
            return q.name;
          }),
          labels: {
            step: 4
          }
        },
        yAxis: {
          title: {
            text: "Hacker Mentions (adjusted for growth)",
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
        },
        series: []
      };
      nullFill = _.map(this.quarters, function(q) {
        return null;
      });
      _.each(this.terms, function(term) {
        return options.series.push({
          name: term,
          id: term,
          data: nullFill
        });
      });
      return this.chart = new Highcharts.Chart(options);
    };

    HNTrends.prototype.getTerms = function() {
      var _this = this;
      return $.getJSON("/terms", {
        q: this.terms.join(",")
      }, function(data) {
        _this.clientId = data.clientId;
        return _this.getMore();
      });
    };

    HNTrends.prototype.getMore = function() {
      var _this = this;
      return $.getJSON("/more", {
        clientId: this.clientId
      }, function(data) {
        if (data.noop) {
          return _this.getMore();
        } else {
          data.hits = parseInt(data.hits, 10);
          _this.pendingPlots.push(data);
          if (!data.last) return _this.getMore();
        }
      });
    };

    HNTrends.prototype.getParam = function(name) {
      var regex, results;
      name = name.replace(/[\[]/, "\\\[").replace(/[\]]/, "\\\]");
      regex = new RegExp("[\\?&]" + name + "=([^&#]*)");
      results = regex.exec(window.location.href);
      if (!results) return "";
      return decodeURIComponent(results[1].replace(/\+/g, " "));
    };

    HNTrends.prototype.plotPending = function() {
      var adjusted, data, quarter, series;
      data = this.pendingPlots.shift();
      if (!data) {
        clearInterval(this.interval);
        return;
      }
      series = this.chart.get(data.term);
      series.next || (series.next = 0);
      quarter = this.quarters[series.next];
      adjusted = parseInt(data.hits * quarter.factor, 10);
      series.data[series.next].update({
        y: adjusted,
        actual: data.hits
      });
      return series.next++;
    };

    return HNTrends;

  })();

  $(function() {
    window.HNT = new HNTrends();
    return $("#more").click(function(event) {
      return $("#lightbox").lightbox_me({
        centered: true
      });
    });
  });

}).call(this);
