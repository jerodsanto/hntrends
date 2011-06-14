(function() {
  var HNTrends;
  HNTrends = (function() {
    function HNTrends() {
      this.initSocket();
      this.initTerms();
      this.initChart();
    }
    HNTrends.prototype.initSocket = function() {
      this.socket = new io.Socket;
      this.socket.connect();
      return this.socket.on("message", this.handleMessage);
    };
    HNTrends.prototype.initTerms = function() {
      var termList, terms;
      terms = this.getParam("q");
      if (terms.length) {
        $("input[type=text]:first").val(terms);
        termList = terms.split(",");
        this.terms = _.map(termList, function(t) {
          return t.trim().toLowerCase();
        });
        return this.submitTerms();
      }
    };
    HNTrends.prototype.initChart = function() {
      var options;
      options = {
        chart: {
          renderTo: "chart",
          defaultsSeriesType: "Line",
          height: 400
        },
        title: null
      };
      return this.chart = new Highcharts.Chart(options);
    };
    HNTrends.prototype.submitTerms = function(terms) {
      return this.socket.send(_.first(this.terms, 5));
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
      return $("#chart").append("<p>" + message.quarter + ": " + message.hits + "</p>");
    };
    return HNTrends;
  })();
  $(function() {
    return window.HNTrends = new HNTrends();
  });
}).call(this);
