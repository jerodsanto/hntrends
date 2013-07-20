$.ajaxSetup {
    cache: false
}

class HNTrends
    constructor: (@pendingPlots = [], @maxY = 100, @clientId) ->
        @initTerms()

    initTerms: ->
        terms = @getParam "q"
        input = $("input[type=text]:first")

        if terms.length
            input.val terms
            $(".twitter-share-button").attr "data-url", "#{window.location.host}/q=#{terms}"
            termList = terms.split ","
            @terms = _.map termList, (t) ->
                return $.trim t.toLowerCase()
            @terms = _.first(@terms, 5)
            # interval depends on how many terms we'll be plotting
            interval = switch @terms.length
                when 1 then 450
                when 2 then 300
                else 250

            setTimeout =>
                @interval = setInterval @plotPending, interval
            , 500

            @getQuarters()
        else
            input.focus()

    getQuarters: ->
        $.getJSON "/quarters", (data) =>
            @quarters = data
            @initChart()
            @getTerms()

    initChart: ->
        $("#examples").hide()
        options =
            colors: ["#FF0000", "#FFCC00", "#6699FF", "#8C1A99", "#99FF00"]
            chart:
                renderTo: "chart"
            title: null
            tooltip:
                crosshairs: true
                formatter: ->
                    a = Highcharts.numberFormat(this.y, 0, ",")
                    b = Highcharts.numberFormat(this.point.actual, 0, ",")
                    "<b>#{this.series.name}</b>in #{this.x}: #{a} adjusted (#{b} actual)"
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
                categories: _.map(@quarters, (q) -> return q.name)
                labels:
                    step: 4
            yAxis:
                title:
                    text: "Hacker Mentions (adjusted for growth)"
                    style:
                        color: "#ff6600"
                labels:
                    align: "left"
                    x: 0
                    y: -2
                min: 0
            plotOptions:
                series:
                    cursor: "pointer"
                    point:
                        events:
                            click: @getTopStories
                line:
                    lineWidth: 4
                    states:
                        hover:
                            lineWidth: 5
                marker:
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
                data.hits = parseInt data.hits, 10
                # just add new data to pendingPlots queue to be processed
                @pendingPlots.push data
                @getMore() unless data.last

    getParam: (name) ->
        name    = name.replace(/[\[]/,"\\\[").replace(/[\]]/,"\\\]")
        regex   = new RegExp "[\\?&]" + name + "=([^&#]*)"
        results = regex.exec window.location.href
        return "" unless results
        return decodeURIComponent results[1].replace(/\+/g, " ")

    getTopStories: (event) =>
        $stories = $("#stories")
        quarter = @quarters[event.target.x]
        term = event.target.series.name

        params =
            clientId: @clientId
            term: term
            quarter: event.target.x

        $stories
            .find("h3")
                .text("Top 10 #{term} stories during #{quarter.name}")
                .end()
            .find(".stories")
                .html("<div class='spinner'></div>")
                .end()
            .lightbox_me {centered: true}

        $.getJSON "/stories", params, (stories) =>
            if stories.length == 0
                html = "<p>No stories found :(</p>"
            else
                html = "<ol>"
                html += _.map(stories, (s) ->
                    "<li><a href='https://news.ycombinator.com/item?id=#{s.id}' target='_blank'>#{s.title}</a> (#{s.points} points)</li>"
                ).join ""
                html += "</ol>"

            $stories.find(".stories").html html

    plotPending: =>
        data = @pendingPlots.shift()

        if !data
            clearInterval @interval
            return

        series = @chart.get data.term
        # store the index of the next null point to be filled on the series
        series.next or= 0
        quarter  = @quarters[series.next]
        adjusted = parseInt(data.hits * quarter.factor, 10)
        series.data[series.next].update({y: adjusted, actual: data.hits})
        series.next++

$ ->
    window.HNT = new HNTrends()

    $("#more").click (event) ->
        $("#about").lightbox_me {centered: true}
