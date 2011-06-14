class HNTrends
  constructor: ->
    @initSocket()
    @initTerms()
    @initChart()

  initSocket: ->
    @socket = new io.Socket
    @socket.connect()
    @socket.on "message", @handleMessage

  initTerms: ->
    terms = @getParam "q"

    if terms.length
      $("input[type=text]:first").val terms
      termList = terms.split ","
      @terms = _.map termList, (t) ->
        return t.trim().toLowerCase()
      @submitTerms()

  initChart: ->
    options =
      chart:
        renderTo: "chart"
        defaultsSeriesType: "Line"
        height: 400
      title: null

    @chart = new Highcharts.Chart(options)

  submitTerms: (terms) ->
    @socket.send _.first(@terms, 5)

  getParam: (name) ->
    name    = name.replace(/[\[]/,"\\\[").replace(/[\]]/,"\\\]")
    regex   = new RegExp "[\\?&]" + name + "=([^&#]*)"
    results = regex.exec window.location.href
    return "" unless results
    return decodeURIComponent results[1].replace(/\+/g, " ")

  handleMessage: (message) ->
    $("#chart").append("<p>#{message.quarter}: #{message.hits}</p>")

$ ->
  window.HNTrends = new HNTrends()
