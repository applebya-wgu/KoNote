# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0 
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# React widget to drop in wherever events should be displayed
# 2 display formats: large and small

Moment = require 'moment'
Persist = require './persist'

load = (win) ->
	$ = win.jQuery
	React = win.React
	R = React.DOM
	{FaIcon, openWindow, renderLineBreaks, showWhen} = require('./utils').load(win)	
	
	progEventsWidget = React.createFactory React.createClass
		mixins: [React.addons.PureRenderMixin]
		getInitialState: ->
			return {
				title: @props.data.get 'title'
				description: @props.data.get 'description'
				eventDate: @_niceDate @props.data.get('startTimestamp'), @props.data.get('endTimestamp')
			}

		componentDidMount: ->
			tooltipContent = R.div({},
				@state.eventDate
				R.br()
				@state.description
			)

			if @props.format is 'small'
				$widget = $(@refs.widget.getDOMNode())

				$widget.tooltip {
					html: true
					title: React.renderToString tooltipContent
					placement: 'auto'
					# required to stop tooltip from being obstructed by menu
					viewport: $widget
				}
		render: ->
			return R.div({
				className: "progEventsWidget #{@props.format}"
			},
				(switch @props.format
					when 'large', 'print'
						R.div({
							ref: 'widget'
							className: 'progEventContainer'
						},
							R.h5({className: 'title'},
								FaIcon 'calendar'
								@state.title
							)
							R.div({className: 'description'},
								renderLineBreaks @state.description
								R.div({className: 'date'}, @state.eventDate)
							)
						)
					when 'small'
						R.div({
							ref: 'widget'
							className: 'progEventContainer'
						},
							FaIcon 'calendar'
							@state.title
						)
					else
						throw new Error "Unknown progEventsWidget format: #{@props.format}"
				)
			)

		_niceDate: (start, end) ->
			startDate = Moment(start, Persist.TimestampFormat).format 'MMMM D, YYYY'
			startTime = Moment(start, Persist.TimestampFormat).format 'HH:mm'
			endDate = Moment(end, Persist.TimestampFormat).format 'MMMM D, YYYY'
			endTime = Moment(end, Persist.TimestampFormat).format 'HH:mm'
			if (startDate is endDate) and (startTime is '00:00') and (endTime is '23:59')
				# single day
				eventDate = startDate
			else if endDate is 'Invalid date'
				# single day + time
				eventDate = [startDate, ' at ', startTime]
			else
				# multiple dates
				eventDate = [startDate, ' - ', endDate]
			eventDate
	
	return progEventsWidget

module.exports = {load}