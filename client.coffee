class HNTrends
  constructor: (@pendingPlots = [], @maxY = 100, @clientId)->
    @initTerms()

  initTerms: ->
    terms = @getParam "q"

    if terms.length
      $("input[type=text]:first").val terms
      termList = terms.split ","
      @terms = _.map termList, (t) ->
        return $.trim t.toLowerCase()
      @terms = _.first(@terms, 5)
      @initChart()
      @getTerms()
      # interval depends on how many terms we'll be plotting
      interval = switch @terms.length
        when 1 then 425
        when 2 then 225
        else 200
      setInterval @plotPending, interval


  initChart: ->
    $("#examples").hide()
    options =
      colors: ["#FFFFFF", "#E90000", "#FFCC00", "#6699FF", "#8C1A99", "#99FF00"]
      chart:
        renderTo: "chart"
        ignoreHiddenSeries: false
      title: null
      legend:
        itemHiddenStyle:
          color: "#FFF"
        itemStyle:
          color: "#666"
        borderWidth: 0
        floating: true
        layout: "vertical"
        align: "left"
        x: 70
        verticalAlign: "top"
        y: -7
      xAxis:
        categories: ["2007", "Q2 2007", "Q3 2007", "Q4 2007"
        "2008", "Q2 2008", "Q3 2008", "Q4 2008", "2009", "Q2 2009",
        "Q3 2009", "Q4 2009", "2010", "Q2 2010", "Q3 2010", "Q4 2010", "2011"]
        labels:
          step: 4
      yAxis:
        title:
          text: "Hacker Mentions"
          style:
            color: "#ff6600"
        labels:
          align: "left"
          x: 0
          y: -2
        max: @maxY
        min: 0
      plotOptions:
        line:
          lineWidth: 4
          states:
            hover:
              lineWidth: 5
          marker:
            enabled: false
            states:
              hover:
                enabled: true
                symbol: "circle"
                radius: 5
                lineWidth: 1

      series: [{
        name: "oh hai!"
        id: "skeleton"
        data: [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]
      }]

    _.each @terms, (term) ->
      options.series.push {name: term, id: term}

    @chart = new Highcharts.Chart(options)
    @chart.get("skeleton").hide()

  getTerms: ->
    $.getJSON "/terms", {q: @terms.join(",")}, (data) =>
      @clientId = data.clientId
      @getMore()

  getMore: ->
    $.getJSON "/more", {clientId: @clientId}, (data) =>
      if data.noop
        @getMore()
      else
        data.hits = parseInt data.hits
        if data.hits > @maxY
          @maxY = data.hits
          @chart.yAxis[0].setExtremes(0, @maxY, true, false)
        # just add new data to pendingPlots queue to be processed
        @pendingPlots.push data
        @getMore() unless data.last

  getParam: (name) ->
    name    = name.replace(/[\[]/,"\\\[").replace(/[\]]/,"\\\]")
    regex   = new RegExp "[\\?&]" + name + "=([^&#]*)"
    results = regex.exec window.location.href
    return "" unless results
    return decodeURIComponent results[1].replace(/\+/g, " ")

  plotPending: =>
    data = @pendingPlots.shift()
    return unless data
    @chart.get(data.term).addPoint(data.hits)

$ ->
  $.ajaxSetup {
    cache: false
  }
  window.HNTrends = new HNTrends()
