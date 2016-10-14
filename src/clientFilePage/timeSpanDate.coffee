# Copyright (c) Konode. All rights reserved.
# This source code is subject to the terms of the Mozilla Public License, v. 2.0
# that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

# Date component for analysisTab which opens a bootbox datetimepicker

Moment = require 'moment'
_ = require 'underscore'

Config = require '../config'


load = (win) ->
	$ = win.jQuery
	React = win.React
	R = React.DOM

	{FaIcon} = require('../utils').load(win)


	# TODO: Switch this out for a proper binding component
	TimeSpanDate = React.createFactory React.createClass
		displayName: 'TimeSpanDate'
		mixins: [React.addons.PureRenderMixin]

		componentDidMount: ->
			# Assess min/maxDate based on which TimeSpanDate type
			if @props.type is 'start'
				minDate = @props.xTicks.first()
				maxDate = @props.timeSpan.get('end')
			else
				minDate = @props.timeSpan.get('start')
				maxDate = @props.xTicks.last()

			# Init datetimepicker
			$(@refs.hiddenDateTimePicker).datetimepicker({
				format: Config.dateFormat
				useCurrent: false
				defaultDate: @props.date
				minDate
				maxDate

				toolbarPlacement: 'bottom'
				widgetPositioning: {
					vertical: 'bottom'
				}
			}).on 'dp.change', @_onChange

			@dateTimePicker = $(@refs.hiddenDateTimePicker).data('DateTimePicker')

		componentDidUpdate: (oldProps) ->
			# TODO: Handle start/end logic in analysis, use generic component

			startPropHasChanged = not oldProps.date.get('start').isSame(@props.timeSpan.get('start'))
			startDateIsNew = not @dateTimePicker.date().isSame(@props.timeSpan.get('start'))

			if startPropHasChanged and startDateIsNew
				startDate = @props.timeSpan.get('start')

				if @props.type is 'start'
					# Update 'start' datetimepicker
					@dateTimePicker.date startDate
				else
					# Catch bad updates
					if startDate.isAfter @dateTimePicker.maxDate()
						return console.warn "Tried to make minDate > maxDate, update cancelled"

					# For 'end', just adjust the minDate
					@dateTimePicker.minDate startDate


			endPropHasChanged = not oldProps.timeSpan.get('end').isSame @props.timeSpan.get('end')
			endDateIsNew = not @dateTimePicker.date().isSame @props.timeSpan.get('end')

			if endPropHasChanged and endDateIsNew
				endDate = @props.timeSpan.get('end')

				if @props.type is 'end'
					# Update 'end' datetimepicker
					@dateTimePicker.date endDate
				else
					# Catch bad updates
					if endDate.isBefore @dateTimePicker.minDate()
						return console.warn "Tried to make maxDate < minDate, update cancelled"

					# For 'start', just adjust the maxDate
					@dateTimePicker.maxDate endDate

		_onChange: (event) ->
			# Needs to be created in millisecond format to stay consistent
			newDate = Moment +Moment(event.target.value, Config.dateFormat)
			@props.updateTimeSpanDate(newDate, @props.type)

		_toggleDateTimePicker: -> @dateTimePicker.toggle()

		render: ->
			return null unless @props.date

			formattedDate = @props.date.format(Config.dateFormat)

			return R.div({className: 'timeSpanDate'},
				R.span({
					onClick: @_toggleDateTimePicker
					className: 'date'
				},
					R.input({
						ref: 'hiddenDateTimePicker'
						id: "datetimepicker-#{@props.type}"
					})
					R.span({}, formattedDate)
					R.span({}, FaIcon('caret-down'))
				)
			)

	return TimeSpanDate

module.exports = {load}