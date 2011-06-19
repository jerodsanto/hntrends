class HNTrends
  constructor: (@pendingPlots = [], @maxY = 100, @clientId)->
    @quarters = [
      "2007", "Q2 2007", "Q3 2007", "Q4 2007"
    "2008", "Q2 2008", "Q3 2008", "Q4 2008",
      "2009", "Q2 2009", "Q3 2009", "Q4 2009",
    "2010", "Q2 2010", "Q3 2010", "Q4 2010",
    "2011"
    ]
    @initTerms()

  initTerms: ->
    terms = @getParam "q"
    input = $("input[type=text]:first")

    if terms.length
      input.val terms
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
    else
      input.focus()


  initChart: ->
    $("#examples").hide()
    options =
      colors: ["#FF0000", "#FFCC00", "#6699FF", "#8C1A99", "#99FF00"]
      chart:
        renderTo: "chart"
      title: null
      legend:
        itemStyle:
          color: "#666"
        borderWidth: 0
        floating: true
        layout: "vertical"
        align: "left"
        x: 70
        verticalAlign: "top"
        y: 0
      xAxis:
        categories: @quarters
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
      series: []

    # using this as series data allows the categories to be static
    nullFill = _.map @quarters, (q) -> null

    _.each @terms, (term) ->
      options.series.push {name: term, id: term, data: nullFill }

    @chart = new Highcharts.Chart(options)

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
    series = @chart.get(data.term)
    # store the index of the next null point to be filled on the series
    series.next or= 0
    series.data[series.next].update(data.hits)
    series.next++

$ ->
  $.ajaxSetup {
    cache: false
  }
  window.HNTrends = new HNTrends()
